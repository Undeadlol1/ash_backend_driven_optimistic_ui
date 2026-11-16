defmodule AshBackendDrivenOptimisticUi.JsonLogic do
  @moduledoc """
  Evaluates JSON Logic the way the client does: the full standard (`var`,
  `missing`, `missing_some`, `if`, `?:`, `== != === !==`, `! !!`, `or`, `and`,
  `> >= < <=` including the three-operand "between" form, `max`, `min`,
  `+ - * / %`, `map`, `filter`, `reduce`, `all`, `none`, `some`, `merge`, `in`,
  `cat`, `substr`, `log`), checked against the official JSON Logic test suite,
  plus five custom operations: `has` (whether a dotted path's last key is
  present, even with a null value), `abs`, `round` (one or two operands, half
  away from zero), `to_string` (`nil` becomes empty text) and `now` (the
  current UTC time as ISO 8601 text). Literals pass through and a list that is
  not an operation evaluates each element.

  Where JavaScript would produce `NaN`, which JSON cannot carry, this raises
  `ArgumentError` instead: arithmetic (`+ - * / % min max abs round`) accepts
  only numbers and numeric strings. An unknown operation, or a map holding more
  than one operation, raises too. Comparison with `<`, `>`, `<=` and `>=` never
  raises: two texts compare as text, anything else compares as numbers, and a
  side that is not numeric makes the result `false`.

  `cat` prints `nil` as `null` and a whole float without its fraction.
  """

  @doc "Evaluates `rule` against `data`, a map with string keys."
  @spec run(term(), term()) :: term()
  def run(%{} = rule, data) when map_size(rule) == 1 do
    [{operator, operands}] = Map.to_list(rule)
    apply_operator(operator, List.wrap(operands), data)
  end

  def run(%{} = rule, _data), do: raise(ArgumentError, "not a JSON Logic rule: #{inspect(rule)}")
  def run(list, data) when is_list(list), do: Enum.map(list, &run(&1, data))
  def run(literal, _data), do: literal

  defp apply_operator(operator, operands, data) when operator in ["if", "?:"], do: choose(operands, data)
  defp apply_operator("and", operands, data), do: short_circuit(operands, data, &(not truthy?(&1)))
  defp apply_operator("or", operands, data), do: short_circuit(operands, data, &truthy?/1)
  defp apply_operator("map", [source, logic | _], data), do: Enum.map(scoped_list(source, data), &run(logic, &1))

  defp apply_operator("filter", [source, logic | _], data),
    do: Enum.filter(scoped_list(source, data), &truthy?(run(logic, &1)))

  defp apply_operator("reduce", [source, logic | rest], data) do
    initial = rest |> List.first() |> run(data)
    scope = fn current, accumulator -> %{"current" => current, "accumulator" => accumulator} end

    source
    |> scoped_list(data)
    |> Enum.reduce(initial, fn current, accumulator -> run(logic, scope.(current, accumulator)) end)
  end

  defp apply_operator("all", [source, logic | _], data) do
    case scoped_list(source, data) do
      [] -> false
      items -> Enum.all?(items, &truthy?(run(logic, &1)))
    end
  end

  defp apply_operator("none", [source, logic | _], data),
    do: not Enum.any?(scoped_list(source, data), &truthy?(run(logic, &1)))

  defp apply_operator("some", [source, logic | _], data),
    do: Enum.any?(scoped_list(source, data), &truthy?(run(logic, &1)))

  defp apply_operator(operator, operands, data), do: evaluated(operator, Enum.map(operands, &run(&1, data)), data)

  defp evaluated("var", values, data), do: variable(values, data)
  defp evaluated("has", [path], data), do: present?(data, String.split(path, "."))
  defp evaluated("missing", values, data), do: missing(values, data)
  defp evaluated("missing_some", [needed, keys], data), do: missing_some(needed, keys, data)
  defp evaluated(operator, values, _data), do: evaluated(operator, values)

  defp evaluated("+", values), do: values |> Enum.map(&number/1) |> Enum.sum()
  defp evaluated("-", [value]), do: -number(value)
  defp evaluated("-", [left, right]), do: number(left) - number(right)
  defp evaluated("*", [_ | _] = values), do: values |> Enum.map(&number/1) |> Enum.reduce(&(&1 * &2))
  defp evaluated("/", [left, right]), do: divide(number(left), number(right))
  defp evaluated("%", [left, right]), do: remainder(number(left), number(right))
  defp evaluated("min", [_ | _] = values), do: values |> Enum.map(&number/1) |> Enum.min()
  defp evaluated("max", [_ | _] = values), do: values |> Enum.map(&number/1) |> Enum.max()
  defp evaluated("==", [left, right]), do: loose_equal?(left, right)
  defp evaluated("!=", [left, right]), do: not loose_equal?(left, right)
  defp evaluated("===", [left, right]), do: left == right
  defp evaluated("!==", [left, right]), do: left != right
  defp evaluated("<", values), do: ordered?(values, &</2)
  defp evaluated(">", values), do: ordered?(values, &>/2)
  defp evaluated("<=", values), do: ordered?(values, &<=/2)
  defp evaluated(">=", values), do: ordered?(values, &>=/2)
  defp evaluated("!", [value]), do: not truthy?(value)
  defp evaluated("!!", [value]), do: truthy?(value)
  defp evaluated("log", [value | _]), do: value
  defp evaluated("merge", values), do: Enum.flat_map(values, &listify/1)
  defp evaluated("cat", values), do: Enum.map_join(values, &text/1)
  defp evaluated("substr", [source, start]), do: substr(text(source), start, nil)
  defp evaluated("substr", [source, start, length]), do: substr(text(source), start, length)
  defp evaluated("in", [needle, haystack]) when is_binary(haystack), do: String.contains?(haystack, text(needle))
  defp evaluated("in", [needle, haystack]) when is_list(haystack), do: Enum.any?(haystack, &(&1 == needle))
  defp evaluated("in", [_needle, _haystack]), do: false
  defp evaluated("abs", [value]), do: abs(number(value))
  defp evaluated("round", [value]), do: round(number(value))
  defp evaluated("round", [value, places]), do: Float.round(number(value) * 1.0, trunc(number(places)))
  defp evaluated("to_string", [nil]), do: ""
  defp evaluated("to_string", [value]), do: text(value)
  defp evaluated("now", []), do: DateTime.to_iso8601(DateTime.utc_now())

  defp evaluated(operator, operands),
    do: raise(ArgumentError, "unknown JSON Logic operation #{inspect(operator)} with #{length(operands)} operands")

  defp choose([condition, then_branch | rest], data) do
    if truthy?(run(condition, data)), do: run(then_branch, data), else: choose(rest, data)
  end

  defp choose([last], data), do: run(last, data)
  defp choose([], _data), do: nil

  defp listify(value) when is_list(value), do: value
  defp listify(value), do: [value]

  defp scoped_list(source, data) do
    case run(source, data) do
      list when is_list(list) -> list
      _not_a_list -> []
    end
  end

  defp number(value) do
    case parse_number(value) do
      {:ok, number} -> number
      :error -> raise ArgumentError, "Not a number: #{inspect(value)}"
    end
  end

  defp parse_number(value) when is_number(value), do: {:ok, value}

  defp parse_number(value) when is_binary(value) do
    trimmed = value |> String.trim() |> String.replace_prefix(".", "0.")

    case {Integer.parse(trimmed), Float.parse(trimmed)} do
      _empty when trimmed == "" -> {:ok, 0}
      {{integer, ""}, _float} -> {:ok, integer}
      {_integer, {float, ""}} -> {:ok, float}
      _neither -> :error
    end
  end

  defp parse_number(_value), do: :error

  defp ordering_number(nil), do: {:ok, 0}
  defp ordering_number(true), do: {:ok, 1}
  defp ordering_number(false), do: {:ok, 0}
  defp ordering_number(value), do: parse_number(value)

  defp divide(_left, right) when right == 0, do: raise(ArgumentError, "division by zero")
  defp divide(left, right), do: left / right

  defp remainder(_left, right) when right == 0, do: raise(ArgumentError, "remainder by zero")
  defp remainder(left, right) when is_integer(left) and is_integer(right), do: rem(left, right)
  defp remainder(left, right), do: :math.fmod(left, right)

  defp ordered?([left, right], compare), do: compare_pair(left, right, compare)

  defp ordered?([left, middle, right], compare),
    do: compare_pair(left, middle, compare) and compare_pair(middle, right, compare)

  defp ordered?(values, _compare), do: raise(ArgumentError, "cannot order #{length(values)} operands")

  defp compare_pair(left, right, compare) when is_binary(left) and is_binary(right), do: compare.(left, right)

  defp compare_pair(left, right, compare) do
    case {ordering_number(left), ordering_number(right)} do
      {{:ok, left_number}, {:ok, right_number}} -> compare.(left_number, right_number)
      _not_both_numeric -> false
    end
  end

  defp loose_equal?(nil, right), do: right == nil
  defp loose_equal?(_left, nil), do: false
  defp loose_equal?(left, right) when is_boolean(left), do: loose_equal?(boolean_number(left), right)
  defp loose_equal?(left, right) when is_boolean(right), do: loose_equal?(left, boolean_number(right))

  defp loose_equal?(left, right) when is_number(left) and is_binary(right), do: numeric_equal?(left, right)
  defp loose_equal?(left, right) when is_binary(left) and is_number(right), do: numeric_equal?(right, left)
  defp loose_equal?(left, right), do: left == right

  defp boolean_number(true), do: 1
  defp boolean_number(false), do: 0

  defp numeric_equal?(number, text) do
    case parse_number(text) do
      {:ok, parsed} -> parsed == number
      :error -> false
    end
  end

  defp variable([], data), do: data
  defp variable([path | _], data) when path in [nil, ""], do: data

  defp variable([path | rest], data) do
    case fetch(data, path |> text() |> String.split(".")) do
      {:ok, value} -> value
      :error -> List.first(rest)
    end
  end

  defp fetch(data, []), do: {:ok, data}
  defp fetch(%{} = map, [key | rest]), do: with({:ok, value} <- Map.fetch(map, key), do: fetch(value, rest))

  defp fetch(list, [key | rest]) when is_list(list) do
    with {index, ""} <- Integer.parse(key),
         {:ok, value} <- Enum.fetch(list, index) do
      fetch(value, rest)
    else
      _no_such_index -> :error
    end
  end

  defp fetch(_data, _path), do: :error

  defp missing([keys | _], data) when is_list(keys), do: missing(keys, data)
  defp missing(keys, data), do: Enum.filter(keys, &(variable([&1], data) in [nil, ""]))

  defp missing_some(needed, keys, data) do
    absent = missing(keys, data)
    if length(keys) - length(absent) >= needed, do: [], else: absent
  end

  defp substr(source, start, length) do
    start_index = if start < 0, do: max(String.length(source) + start, 0), else: start
    rest = String.slice(source, trunc(start_index)..-1//1)

    cond do
      length == nil -> rest
      length < 0 -> String.slice(rest, 0, max(String.length(rest) + trunc(length), 0))
      true -> String.slice(rest, 0, trunc(length))
    end
  end

  defp present?(%{} = map, [key]), do: Map.has_key?(map, key)
  defp present?(%{} = map, [key | rest]), do: present?(Map.get(map, key), rest)
  defp present?(_value, _path), do: false

  defp short_circuit([], _data, _stop?), do: nil
  defp short_circuit([last], data, _stop?), do: run(last, data)

  defp short_circuit([first | rest], data, stop?) do
    value = run(first, data)
    if stop?.(value), do: value, else: short_circuit(rest, data, stop?)
  end

  @doc "JSON Logic truthiness: everything but `false`, `nil`, `0`, `\"\"` and `[]`."
  @spec truthy?(term()) :: boolean()
  def truthy?(value), do: value not in [false, nil, 0, 0.0, "", []]

  defp text(nil), do: "null"
  defp text(value) when is_float(value) and value == trunc(value), do: Integer.to_string(trunc(value))
  defp text(value) when is_list(value), do: Enum.map_join(value, ",", &list_item_text/1)
  defp text(%{}), do: "[object Object]"
  defp text(value), do: to_string(value)

  defp list_item_text(nil), do: ""
  defp list_item_text(value), do: text(value)
end
