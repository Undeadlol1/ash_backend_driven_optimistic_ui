defmodule AshBackendDrivenOptimisticUi.JsonLogic do
  @moduledoc """
  Evaluates the JSON Logic `AshBackendDrivenOptimisticUi.Compiler` emits, the way the client
  does: `var` with dotted paths over string-keyed maps (a missing path is
  `nil`), `+ - * /` (unary `-` negates), `== != < > <= >=`, `and`, `or`, `!`,
  `if`, `cat`, `in`, `abs`, `round`, `to_string`, `now`, and `has` (whether a dotted
  path's last key is present, even with a null value). Literals pass through; any
  other operator raises.

  Arithmetic and ordering parse number strings (`"10"`, `"10.5"`) and raise
  `ArgumentError` for anything that is not a number; `==` and `!=` compare a
  number with a numeric string as numbers. `cat` and `to_string` print a whole
  float without its fraction and `nil` as empty text.
  """

  @doc "Evaluates `rule` against `data`, a map with string keys."
  @spec run(term(), map()) :: term()
  def run(%{} = rule, data) when map_size(rule) == 1 do
    [{operator, operands}] = Map.to_list(rule)
    apply_operator(operator, List.wrap(operands), data)
  end

  def run(%{} = rule, _data), do: raise(ArgumentError, "not a JSON Logic rule: #{inspect(rule)}")
  def run(list, data) when is_list(list), do: Enum.map(list, &run(&1, data))
  def run(literal, _data), do: literal

  defp apply_operator("var", [path], data), do: lookup(data, String.split(path, "."))
  defp apply_operator("has", [path], data), do: present?(data, String.split(path, "."))

  defp apply_operator("and", operands, data), do: short_circuit(operands, data, &(not truthy?(&1)))

  defp apply_operator("or", operands, data), do: short_circuit(operands, data, &truthy?/1)

  defp apply_operator("if", [condition, then_branch, else_branch], data) do
    if truthy?(run(condition, data)), do: run(then_branch, data), else: run(else_branch, data)
  end

  defp apply_operator(operator, operands, data), do: evaluated(operator, Enum.map(operands, &run(&1, data)))

  defp evaluated("+", values), do: values |> Enum.map(&number/1) |> Enum.sum()
  defp evaluated("-", [value]), do: -number(value)
  defp evaluated("-", [left, right]), do: number(left) - number(right)
  defp evaluated("*", values), do: values |> Enum.map(&number/1) |> Enum.reduce(1, &(&1 * &2))
  defp evaluated("/", [left, right]), do: number(left) / number(right)
  defp evaluated("==", [left, right]), do: equal?(left, right)
  defp evaluated("!=", [left, right]), do: not equal?(left, right)
  defp evaluated("<", [left, right]), do: number(left) < number(right)
  defp evaluated(">", [left, right]), do: number(left) > number(right)
  defp evaluated("<=", [left, right]), do: number(left) <= number(right)
  defp evaluated(">=", [left, right]), do: number(left) >= number(right)
  defp evaluated("!", [value]), do: not truthy?(value)
  defp evaluated("cat", values), do: Enum.map_join(values, &text/1)

  defp evaluated("in", [needle, haystack]) when is_binary(haystack), do: String.contains?(haystack, text(needle))

  defp evaluated("in", [needle, haystack]) when is_list(haystack), do: needle in haystack
  defp evaluated("abs", [value]), do: abs(number(value))
  defp evaluated("round", [value]), do: round(number(value))

  defp evaluated("round", [value, places]), do: Float.round(number(value) * 1.0, trunc(number(places)))

  defp evaluated("to_string", [value]), do: text(value)
  defp evaluated("now", []), do: DateTime.to_iso8601(DateTime.utc_now())

  defp evaluated(operator, operands),
    do: raise(ArgumentError, "unknown JSON Logic operation #{inspect(operator)} with #{length(operands)} operands")

  defp number(value) do
    case parse_number(value) do
      {:ok, number} -> number
      :error -> raise ArgumentError, "Not a number: #{inspect(value)}"
    end
  end

  defp parse_number(value) when is_number(value), do: {:ok, value}

  defp parse_number(value) when is_binary(value) do
    trimmed = String.trim(value)

    case {Integer.parse(trimmed), Float.parse(trimmed)} do
      {{integer, ""}, _float} -> {:ok, integer}
      {_integer, {float, ""}} -> {:ok, float}
      _neither -> :error
    end
  end

  defp parse_number(_value), do: :error

  defp equal?(left, right) when is_number(left) or is_number(right) do
    case {parse_number(left), parse_number(right)} do
      {{:ok, left_number}, {:ok, right_number}} -> left_number == right_number
      _not_both_numeric -> left == right
    end
  end

  defp equal?(left, right), do: left == right

  defp lookup(value, []), do: value
  defp lookup(%{} = map, [key | rest]), do: lookup(Map.get(map, key), rest)
  defp lookup(_value, _path), do: nil

  defp present?(%{} = map, [key]), do: Map.has_key?(map, key)
  defp present?(%{} = map, [key | rest]), do: present?(Map.get(map, key), rest)
  defp present?(_value, _path), do: false

  defp short_circuit([last], data, _stop?), do: run(last, data)

  defp short_circuit([first | rest], data, stop?) do
    value = run(first, data)
    if stop?.(value), do: value, else: short_circuit(rest, data, stop?)
  end

  @doc "JSON Logic truthiness: everything but `false`, `nil`, `0`, `\"\"` and `[]`."
  @spec truthy?(term()) :: boolean()
  def truthy?(value), do: value not in [false, nil, 0, "", []]

  defp text(value) when is_float(value) and value == trunc(value), do: Integer.to_string(trunc(value))

  defp text(value), do: to_string(value)
end
