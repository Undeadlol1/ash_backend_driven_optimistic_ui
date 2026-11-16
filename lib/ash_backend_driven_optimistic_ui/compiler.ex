defmodule AshBackendDrivenOptimisticUi.Compiler do
  @moduledoc """
  Compiles an unhydrated `Ash.Expr` term to JSON Logic, as plain maps and
  lists ready for `Jason`.

  Variables: an attribute, calculation or aggregate reads `record.<name>`, an
  argument reads `input.<name>`, a context value reads `ctx.<name>` (a context
  path is dotted, `ctx.copy.title`), `event(:key)` reads `event.<key>`, the
  payload of the pushed event a reaction answers.

  Standard operators: `+ - * /` (and unary `-`), `== != < > <= >=`, `cat`
  (from `<>`, nested ones flattened), `in`, `and`, `or`, `!` (from `not`), `if`; `is_nil(x)` becomes
  `x == nil`; `has_arg(:name)` becomes `has`, true when the input carries the
  key, even with a null value, so a rule can leave alone a field the caller
  did not send.

  Custom operators the client's evaluator implements on top of JSON Logic:

    * `abs` — `abs(x)`
    * `round` — `round(x)` and `round(x, places)`
    * `to_string` — `to_string(x)`
    * `now` — `now()`, the current UTC time as ISO 8601 text
    * `has` — `{"has": "input.name"}`, whether the path's last key is present

  Decimals become floats. Anything else, including references through a
  relationship and the actor, is `{:error, {:unsupported, node}}`.
  """

  alias Ash.Query.BooleanExpression
  alias Ash.Query.Call
  alias Ash.Query.Not
  alias Ash.Query.Ref

  @operators %{
    +: "+",
    -: "-",
    *: "*",
    /: "/",
    ==: "==",
    !=: "!=",
    <: "<",
    >: ">",
    <=: "<=",
    >=: ">=",
    <>: "cat",
    in: "in"
  }

  @custom_functions %{
    {:abs, 1} => "abs",
    {:round, 1} => "round",
    {:round, 2} => "round",
    {:to_string, 1} => "to_string",
    {:now, 0} => "now"
  }

  @type json_logic ::
          number() | String.t() | boolean() | nil | [json_logic()] | %{String.t() => json_logic()}

  @doc "Compiles `expression`, or names the first node the client cannot run."
  @spec compile(term()) :: {:ok, json_logic()} | {:error, {:unsupported, term()}}
  def compile(%Call{name: :<>, args: [_, _]} = concatenation), do: operation("cat", flatten_cat(concatenation))

  def compile(%Call{name: name, args: args}) when is_map_key(@operators, name) and length(args) in [1, 2] do
    operation(@operators[name], args)
  end

  def compile(%Call{name: :if, args: [condition, branches]}) when is_list(branches) do
    operation("if", [condition, Keyword.get(branches, :do), Keyword.get(branches, :else)])
  end

  def compile(%Call{name: :if, args: [_condition, _then, _else] = args}), do: operation("if", args)

  def compile(%Call{name: :is_nil, args: [value]}), do: operation("==", [value, nil])
  def compile(%Call{name: :arg, args: [name]}), do: compile({:_arg, name})

  def compile(%Call{name: :has_arg, args: [name]}) when is_atom(name), do: {:ok, %{"has" => "input.#{name}"}}

  def compile(%Call{name: :event, args: [key]}) when is_atom(key) or is_binary(key), do: variable("event.#{key}")

  def compile(%Call{name: name, args: args} = call) do
    case Map.fetch(@custom_functions, {name, length(args)}) do
      {:ok, operator} -> operation(operator, args)
      :error -> unsupported(call)
    end
  end

  def compile(%BooleanExpression{op: operator} = expression) do
    operation(Atom.to_string(operator), flatten(expression, operator))
  end

  def compile(%Not{expression: expression}), do: operation("!", [expression])

  def compile(%Ref{attribute: attribute, relationship_path: []}) when is_atom(attribute) do
    variable("record.#{attribute}")
  end

  def compile({:_arg, name}), do: variable("input.#{name}")
  def compile({:_context, path}) when is_list(path), do: variable("ctx." <> Enum.join(path, "."))
  def compile({:_context, name}) when is_atom(name), do: variable("ctx.#{name}")
  def compile(%Decimal{} = decimal), do: {:ok, Decimal.to_float(decimal)}

  def compile(literal) when is_number(literal) or is_binary(literal) or is_boolean(literal) or is_nil(literal),
    do: {:ok, literal}

  def compile(atom) when is_atom(atom), do: {:ok, Atom.to_string(atom)}
  def compile(list) when is_list(list), do: compile_all(list)
  def compile(node), do: unsupported(node)

  defp operation(operator, operands) do
    with {:ok, compiled} <- compile_all(operands), do: {:ok, %{operator => compiled}}
  end

  defp compile_all(terms) do
    terms
    |> Enum.reduce_while({:ok, []}, fn term, {:ok, compiled} ->
      case compile(term) do
        {:ok, value} -> {:cont, {:ok, [value | compiled]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, compiled} -> {:ok, Enum.reverse(compiled)}
      error -> error
    end
  end

  defp flatten(%BooleanExpression{op: operator, left: left, right: right}, operator),
    do: flatten(left, operator) ++ flatten(right, operator)

  defp flatten(operand, _operator), do: [operand]

  defp flatten_cat(%Call{name: :<>, args: [left, right]}), do: flatten_cat(left) ++ flatten_cat(right)

  defp flatten_cat(operand), do: [operand]

  defp variable(path), do: {:ok, %{"var" => path}}
  defp unsupported(node), do: {:error, {:unsupported, node}}
end
