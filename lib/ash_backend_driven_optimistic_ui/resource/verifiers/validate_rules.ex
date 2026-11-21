defmodule AshBackendDrivenOptimisticUi.Resource.Verifiers.ValidateRules do
  @moduledoc """
  Rejects a `optimistic_ui` block the client could not run or that would drift
  from the resource: an action that is missing or a read, a `set` on
  something that is neither an attribute nor a public calculation, an `arg`
  that is neither an argument nor an accepted attribute of the action (or any `arg` inside `on`), an `event` outside
  `on`, a reference to an unknown field, through a relationship, or to the
  actor, and an expression `AshBackendDrivenOptimisticUi.Compiler` cannot compile.

  `insert` is only for a create; `remove` is for any action on a record
  already in the list (a destroy, or an update after which the list no longer
  shows it); `edit` changes a row already there, so not in a create either. An insert `at: {:sorted_by, field}` must sort by an attribute.
  Their nested list path (`into:` / `from:`), and a `clear`'s, must end in
  the key of the list and its matches follow the same expression rules.

  A `push` that sets its own `id:` is rejected too: ids come from
  `AshBackendDrivenOptimisticUi.PushId`, never from a rule.

  Whether some other resource pushes an `on` event is a cross-resource
  question and is not checked here.
  """

  use Spark.Dsl.Verifier

  alias Ash.Query.BooleanExpression
  alias Ash.Query.Call
  alias Ash.Query.Not
  alias Ash.Query.Ref
  alias Ash.Resource.Info
  alias AshBackendDrivenOptimisticUi.Compiler
  alias AshBackendDrivenOptimisticUi.Effect.Insert
  alias AshBackendDrivenOptimisticUi.Effect.Push
  alias AshBackendDrivenOptimisticUi.Effect.Remove
  alias AshBackendDrivenOptimisticUi.Effect.Set
  alias AshBackendDrivenOptimisticUi.Effect.Where
  alias AshBackendDrivenOptimisticUi.NotOptimistic
  alias AshBackendDrivenOptimisticUi.Reaction
  alias AshBackendDrivenOptimisticUi.Rule
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @rule_types [:create, :update, :destroy, :action]

  @doc false
  def verify(dsl_state) do
    entities = Verifier.get_entities(dsl_state, [:optimistic_ui])

    entities
    |> Enum.map(&entity_result(dsl_state, entities, &1))
    |> Enum.find(:ok, &match?({:error, _reason}, &1))
  end

  defp entity_result(dsl_state, entities, entity) do
    case problem(dsl_state, entities, entity) do
      nil -> :ok
      message -> {:error, error(dsl_state, entity, message)}
    end
  end

  defp problem(dsl_state, entities, %Rule{action: name} = rule) do
    opt_out_problem(entities, rule) || rule_problem(dsl_state, name, rule)
  end

  defp problem(dsl_state, entities, %NotOptimistic{action: name}) do
    case Info.action(dsl_state, name) do
      nil ->
        "no action #{inspect(name)} on this resource"

      %{type: type} when type not in @rule_types ->
        "#{inspect(name)} is a #{type} action; not_optimistic needs a create, update, destroy or generic action"

      _action ->
        twice_problem(entities, name)
    end
  end

  defp problem(dsl_state, _entities, %Reaction{effects: effects}), do: effects_problem(dsl_state, effects, :reaction)

  defp opt_out_problem(entities, %Rule{action: name}) do
    if Enum.any?(entities, &match?(%NotOptimistic{action: ^name}, &1)),
      do: "#{inspect(name)} has both `optimistic` and `not_optimistic`; keep one"
  end

  defp twice_problem(entities, name) do
    if Enum.count(entities, &match?(%NotOptimistic{action: ^name}, &1)) > 1,
      do: "#{inspect(name)} is named twice in `not_optimistic`; keep one line"
  end

  defp rule_problem(dsl_state, name, rule) do
    case Info.action(dsl_state, name) do
      nil ->
        "no action #{inspect(name)} on this resource"

      %{type: type} when type not in @rule_types ->
        "#{inspect(name)} is a #{type} action; rules need a create, update, destroy or generic action"

      action ->
        argument_names =
          action.arguments
          |> MapSet.new(& &1.name)
          |> MapSet.union(MapSet.new(Map.get(action, :accept) || []))

        list_problem(action.type, rule.effects) ||
          effects_problem(dsl_state, rule.effects, {:action, name, argument_names})
    end
  end

  defp list_problem(type, effects) do
    cond do
      type != :create and Enum.any?(effects, &match?(%Insert{}, &1)) ->
        "`insert` adds the new record to a list; only a create makes one"

      type == :create and Enum.any?(effects, &match?(%Remove{}, &1)) ->
        "`remove` takes a record out of a list; a create has none there yet"

      type == :create and
          Enum.any?(effects, &match?(%AshBackendDrivenOptimisticUi.Effect.Edit{}, &1)) ->
        "`edit` changes a row already in a list; a create has none there yet"

      true ->
        nil
    end
  end

  defp effects_problem(dsl_state, effects, arguments) do
    Enum.find_value(effects, &effect_problem(dsl_state, &1, arguments))
  end

  defp effect_problem(dsl_state, %Set{attribute: attribute, value: value, from: from}, arguments) do
    problem =
      if settable?(dsl_state, attribute),
        do: expression_problem(dsl_state, value, arguments),
        else:
          "`set #{inspect(attribute)}`: #{inspect(attribute)} is not an attribute or public calculation of this resource"

    if problem && from, do: "#{inspect(from)}.optimistic_sets/1: #{problem}", else: problem
  end

  defp effect_problem(dsl_state, %Push{event: event, payload: payload}, arguments) do
    if Keyword.has_key?(payload, :id),
      do:
        "`push #{inspect(event)}` must not set `id:`; the push id is computed from the record " <>
          "and read from ctx.push_ids (see AshBackendDrivenOptimisticUi.PushId)",
      else: expression_problem(dsl_state, Keyword.values(payload), arguments)
  end

  defp effect_problem(dsl_state, %Where{condition: condition, effects: effects}, arguments) do
    expression_problem(dsl_state, condition, arguments) ||
      effects_problem(dsl_state, effects, arguments)
  end

  defp effect_problem(dsl_state, %Insert{at: {:sorted_by, field}, into: path}, arguments) do
    if Info.attribute(dsl_state, field),
      do: path_problem(dsl_state, path, arguments),
      else: "`insert` sorts by #{inspect(field)}, which is not an attribute of this resource"
  end

  defp effect_problem(dsl_state, %Insert{into: path}, arguments), do: path_problem(dsl_state, path, arguments)

  defp effect_problem(dsl_state, %{from: path}, arguments), do: path_problem(dsl_state, path, arguments)

  defp path_problem(_dsl_state, nil, _arguments), do: nil

  defp path_problem(dsl_state, path, arguments) do
    cond do
      not match?([_ | _], path) or not is_atom(List.last(path)) ->
        "a nested list path must end in the key of the list, like `[:groups, :items]`"

      step = Enum.find(path, &(not path_step?(&1))) ->
        "#{inspect(step)} is not a path step; use `:key` or `{:key, field: expr(...)}`"

      true ->
        expression_problem(dsl_state, Enum.flat_map(path, &step_values/1), arguments)
    end
  end

  defp path_step?(key) when is_atom(key), do: true
  defp path_step?({key, match}) when is_atom(key), do: Keyword.keyword?(match)
  defp path_step?(_step), do: false

  defp step_values({_key, match}), do: Keyword.values(match)
  defp step_values(_key), do: []

  defp settable?(dsl_state, name) do
    Info.attribute(dsl_state, name) != nil or
      match?(%{public?: true}, Info.calculation(dsl_state, name))
  end

  defp expression_problem(dsl_state, expression, arguments) do
    first_problem(expression, nil, dsl_state, arguments) || compile_problem(dsl_state, expression, arguments)
  end

  defp compile_problem(dsl_state, expression, arguments) do
    case Compiler.compile(expression, resource: dsl_state, action: action_name(arguments)) do
      {:ok, _compiled} ->
        nil

      {:error, {:unsupported, node}} ->
        "#{trigger_name(arguments)} uses #{inspect(node)}, which the client cannot evaluate " <>
          "(see AshBackendDrivenOptimisticUi.Compiler)"
    end
  end

  defp trigger_name({:action, name, _argument_names}), do: "rule #{inspect(name)}"
  defp trigger_name(:reaction), do: "this reaction"

  defp action_name({:action, name, _argument_names}), do: name
  defp action_name(:reaction), do: nil

  defp first_problem(node, problem, dsl_state, arguments) do
    problem = problem || node_problem(dsl_state, node, arguments)
    node |> children() |> Enum.reduce(problem, &first_problem(&1, &2, dsl_state, arguments))
  end

  defp children(%Call{args: args}), do: args
  defp children(%BooleanExpression{left: left, right: right}), do: [left, right]
  defp children(%Not{expression: expression}), do: [expression]
  defp children(list) when is_list(list), do: list
  defp children(tuple) when is_tuple(tuple), do: Tuple.to_list(tuple)
  defp children(_leaf), do: []

  defp node_problem(_dsl_state, %Call{name: name, args: [argument]}, arguments) when name in [:arg, :has_arg],
    do: argument_problem(argument, arguments)

  defp node_problem(_dsl_state, %Call{name: :event}, {:action, action, _argument_names}),
    do: "event/1 only works inside `on`, which answers a pushed event; #{inspect(action)} is pushed by no event"

  defp node_problem(_dsl_state, {:_arg, name}, arguments), do: argument_problem(name, arguments)

  defp node_problem(_dsl_state, %Ref{relationship_path: [_ | _] = path}, _arguments) do
    "#{Enum.join(path, ".")}: rules cannot follow relationships; expose a calculation"
  end

  defp node_problem(dsl_state, %Ref{attribute: name}, _arguments) do
    if Info.attribute(dsl_state, name) || Info.calculation(dsl_state, name) ||
         Info.aggregate(dsl_state, name),
       do: nil,
       else: "#{inspect(name)} is not an attribute, calculation or aggregate of this resource"
  end

  defp node_problem(_dsl_state, {:_actor, _path}, _arguments), do: actor_problem()
  defp node_problem(_dsl_state, %Call{name: :actor}, _arguments), do: actor_problem()
  defp node_problem(_dsl_state, _node, _arguments), do: nil

  defp argument_problem(_name, :reaction), do: "reactions have no action arguments; read the record or the context"

  defp argument_problem(name, {:action, action, argument_names}) do
    if MapSet.member?(argument_names, name),
      do: nil,
      else: "#{inspect(name)} is not an argument of #{inspect(action)}"
  end

  defp actor_problem, do: "rules cannot read the actor; the client does not hold it"

  defp error(dsl_state, %Rule{action: action}, message),
    do: dsl_error(dsl_state, [:optimistic_ui, :optimistic, action], message)

  defp error(dsl_state, %NotOptimistic{action: action}, message),
    do: dsl_error(dsl_state, [:optimistic_ui, :not_optimistic, action], message)

  defp error(dsl_state, %Reaction{event: event}, message), do: dsl_error(dsl_state, [:optimistic_ui, :on, event], message)

  defp dsl_error(dsl_state, path, message) do
    DslError.exception(
      module: Verifier.get_persisted(dsl_state, :module),
      path: path,
      message: message
    )
  end
end
