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

  Every compared value that is not a number literal is cast to a number with
  `+`, because Ash sends decimals as text and standard JSON Logic would
  compare two such texts as text (`"10.5" >= "9"` is false). The cast is left
  out when either side is known to be text: a text literal, a date or time
  literal (compiled to its ISO 8601 text), or, when `compile/2` is given the
  resource (and the action, for arguments), an attribute or argument of a type
  Ash sends as text (string, atom, date, datetime, time, uuid). Every joined
  value that is not a text literal is wrapped in `to_string`, because
  standard `cat` prints an empty value as `null` and an Ash developer expects
  nothing.

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
  alias Ash.Resource.Info

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

  @comparisons [:<, :>, :<=, :>=]

  @temporal_types [Date, DateTime, NaiveDateTime, Time]

  # The Ash types whose values travel as text.
  @text_types [
    Ash.Type.String,
    Ash.Type.CiString,
    Ash.Type.Atom,
    Ash.Type.Date,
    Ash.Type.UtcDatetime,
    Ash.Type.UtcDatetimeUsec,
    Ash.Type.NaiveDatetime,
    Ash.Type.Time,
    Ash.Type.UUID
  ]

  @custom_functions %{
    {:abs, 1} => "abs",
    {:round, 1} => "round",
    {:round, 2} => "round",
    {:to_string, 1} => "to_string",
    {:now, 0} => "now"
  }

  @type json_logic ::
          number() | String.t() | boolean() | nil | [json_logic()] | %{String.t() => json_logic()}

  @doc """
  Compiles `expression`, or names the first node the client cannot run.

  Options: `resource:` (a resource, or the DSL state of one being built) and
  `action:` (an action name) let the compiler read the types of the attributes
  and arguments the expression names, so it can tell a text comparison from a
  number comparison.
  """
  @spec compile(term(), keyword()) :: {:ok, json_logic()} | {:error, {:unsupported, term()}}
  def compile(expression, opts \\ []), do: node(expression, Map.new(opts))

  defp node(%Call{name: :<>, args: [_, _]} = concatenation, context) do
    operation("cat", concatenation |> flatten_cat() |> Enum.map(&as_text/1), context)
  end

  defp node(%Call{name: name, args: [left, right]}, context) when name in @comparisons do
    operands =
      if text?(left, context) or text?(right, context), do: [left, right], else: [as_number(left), as_number(right)]

    operation(@operators[name], operands, context)
  end

  defp node(%Call{name: name, args: args}, context) when is_map_key(@operators, name) and length(args) in [1, 2] do
    operation(@operators[name], args, context)
  end

  defp node(%Call{name: :if, args: [condition, branches]}, context) when is_list(branches) do
    operation("if", [condition, Keyword.get(branches, :do), Keyword.get(branches, :else)], context)
  end

  defp node(%Call{name: :if, args: [_condition, _then, _else] = args}, context), do: operation("if", args, context)

  defp node(%Call{name: :is_nil, args: [value]}, context), do: operation("==", [value, nil], context)
  defp node(%Call{name: :arg, args: [name]}, context), do: node({:_arg, name}, context)

  defp node(%Call{name: :has_arg, args: [name]}, _context) when is_atom(name), do: {:ok, %{"has" => "input.#{name}"}}

  defp node(%Call{name: :event, args: [key]}, _context) when is_atom(key) or is_binary(key), do: variable("event.#{key}")

  defp node(%Call{name: name, args: args} = call, context) do
    case Map.fetch(@custom_functions, {name, length(args)}) do
      {:ok, operator} -> operation(operator, args, context)
      :error -> unsupported(call)
    end
  end

  defp node(%BooleanExpression{op: operator} = expression, context) do
    operation(Atom.to_string(operator), flatten(expression, operator), context)
  end

  defp node(%Not{expression: expression}, context), do: operation("!", [expression], context)

  defp node(%Ref{attribute: attribute, relationship_path: []}, _context) when is_atom(attribute) do
    variable("record.#{attribute}")
  end

  defp node({:_arg, name}, _context), do: variable("input.#{name}")
  defp node({:_context, path}, _context) when is_list(path), do: variable("ctx." <> Enum.join(path, "."))
  defp node({:_context, name}, _context) when is_atom(name), do: variable("ctx.#{name}")
  defp node(%Decimal{} = decimal, _context), do: {:ok, Decimal.to_float(decimal)}
  defp node(%type{} = moment, _context) when type in @temporal_types, do: {:ok, type.to_iso8601(moment)}

  defp node(literal, _context) when is_number(literal) or is_binary(literal) or is_boolean(literal) or is_nil(literal),
    do: {:ok, literal}

  defp node(atom, _context) when is_atom(atom), do: {:ok, Atom.to_string(atom)}
  defp node(list, context) when is_list(list), do: compile_all(list, context)
  defp node(other, _context), do: unsupported(other)

  defp operation(operator, operands, context) do
    with {:ok, compiled} <- compile_all(operands, context), do: {:ok, %{operator => compiled}}
  end

  defp compile_all(terms, context) do
    terms
    |> Enum.reduce_while({:ok, []}, fn term, {:ok, compiled} ->
      case node(term, context) do
        {:ok, value} -> {:cont, {:ok, [value | compiled]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, compiled} -> {:ok, Enum.reverse(compiled)}
      error -> error
    end
  end

  # An operand that is known to travel as text, so a comparison of it is a text comparison.
  defp text?(operand, _context) when is_binary(operand), do: true
  defp text?(%type{}, _context) when type in @temporal_types, do: true

  defp text?(%Ref{attribute: name, relationship_path: []}, %{resource: resource}),
    do: text_type?(Info.attribute(resource, name))

  defp text?(%Call{name: :arg, args: [name]}, context), do: text?({:_arg, name}, context)
  defp text?({:_arg, name}, %{resource: _resource, action: _action} = context), do: text_type?(argument(context, name))
  defp text?(_operand, _context), do: false

  defp argument(%{resource: resource, action: action}, name) do
    with %{arguments: arguments} = action <- Info.action(resource, action) do
      Enum.find(arguments, &(&1.name == name)) ||
        (name in (Map.get(action, :accept) || []) && Info.attribute(resource, name))
    end
  end

  defp text_type?(%{type: type}), do: Ash.Type.get_type(type) in @text_types
  defp text_type?(_missing), do: false

  defp as_number(operand) when is_number(operand) or is_struct(operand, Decimal), do: operand
  defp as_number(operand), do: %Call{name: :+, args: [operand]}

  defp as_text(operand) when is_binary(operand), do: operand
  defp as_text(operand), do: %Call{name: :to_string, args: [operand]}

  defp flatten(%BooleanExpression{op: operator, left: left, right: right}, operator),
    do: flatten(left, operator) ++ flatten(right, operator)

  defp flatten(operand, _operator), do: [operand]

  defp flatten_cat(%Call{name: :<>, args: [left, right]}), do: flatten_cat(left) ++ flatten_cat(right)

  defp flatten_cat(operand), do: [operand]

  defp variable(path), do: {:ok, %{"var" => path}}
  defp unsupported(node), do: {:error, {:unsupported, node}}
end
