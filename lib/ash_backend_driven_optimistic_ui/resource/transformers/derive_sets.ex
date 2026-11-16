defmodule AshBackendDrivenOptimisticUi.Resource.Transformers.DeriveSets do
  @moduledoc """
  Reads each optimistic action and prepends a derived `set` for every readable
  change: `atomic_update(attr, expr)`, and `set_attribute(attr, v)` with a
  literal or `arg(...)` value. A change module that implements
  `AshBackendDrivenOptimisticUi.Change` describes its own sets. Other change
  modules and changes guarded by `where` are skipped, so a rule never claims
  more than the action shows. A create also gets `set attr, expr(arg(attr))` for every attribute it
  accepts: the new record is built from the input. An update gets the same set
  for each accepted attribute, inside `where expr(has_arg(attr))`: an update
  changes a field only when the input carries it. A declared `set` for the
  same attribute wins, and so does a readable change over an accepted one.
  A destroy rule that declares no effect gets `remove()`.
  """

  use Spark.Dsl.Transformer

  alias Ash.Query.Call
  alias Ash.Resource.Change
  alias Ash.Resource.Info
  alias AshBackendDrivenOptimisticUi.Effect.Remove
  alias AshBackendDrivenOptimisticUi.Effect.Set
  alias AshBackendDrivenOptimisticUi.Effect.Where
  alias AshBackendDrivenOptimisticUi.Rule
  alias Spark.Dsl.Transformer

  @doc false
  def after?(_transformer), do: true

  @doc false
  def transform(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:optimistic_ui])
    |> Enum.filter(&match?(%Rule{}, &1))
    |> Enum.reduce(dsl_state, &derive_into(&2, &1))
    |> then(&{:ok, &1})
  end

  defp derive_into(dsl_state, rule) do
    case Info.action(dsl_state, rule.action) do
      %{changes: changes} = action ->
        declared = declared_attributes(rule.effects)
        from_changes = Enum.flat_map(changes, &derive/1)
        undeclared = &Enum.reject(&1, fn set -> MapSet.member?(declared, set.attribute) end)

        derived =
          action
          |> accepted_sets(from_changes)
          |> undeclared.()
          |> when_sent(action)
          |> Kernel.++(undeclared.(from_changes))

        Transformer.replace_entity(
          dsl_state,
          [:optimistic_ui],
          %{rule | effects: derived ++ declared_or_default(rule.effects, action)},
          &match?(%Rule{action: action} when action == rule.action, &1)
        )

      _missing_or_changeless ->
        dsl_state
    end
  end

  defp declared_or_default([], %{type: :destroy}), do: [%Remove{}]
  defp declared_or_default(effects, _action), do: effects

  defp when_sent(sets, %{type: :update}) do
    for %Set{attribute: attribute} = set <- sets do
      %Where{condition: %Call{name: :has_arg, args: [attribute]}, effects: [set]}
    end
  end

  defp when_sent(sets, _action), do: sets

  defp accepted_sets(%{type: type, accept: accept}, from_changes) when type in [:create, :update] do
    changed = MapSet.new(from_changes, & &1.attribute)

    for attribute <- accept, not MapSet.member?(changed, attribute) do
      %Set{attribute: attribute, value: {:_arg, attribute}, derived?: true}
    end
  end

  defp accepted_sets(_action, _from_changes), do: []

  defp derive(%Change{where: [], change: {Ash.Resource.Change.Atomic, opts}}) do
    [%Set{attribute: opts[:attribute], value: opts[:expr], derived?: true}]
  end

  defp derive(%Change{where: [], change: {Ash.Resource.Change.SetAttribute, opts}}) do
    if readable_value?(opts[:value]),
      do: [%Set{attribute: opts[:attribute], value: opts[:value], derived?: true}],
      else: []
  end

  defp derive(%Change{where: [], change: {module, opts}}) when is_atom(module) do
    Code.ensure_compiled!(module)

    if function_exported?(module, :optimistic_sets, 1) do
      for {attribute, value} <- module.optimistic_sets(opts),
          do: %Set{attribute: attribute, value: value, derived?: true, from: module}
    else
      []
    end
  end

  defp derive(_opaque_change), do: []

  defp readable_value?({:_arg, _name}), do: true
  defp readable_value?(value), do: is_number(value) or is_binary(value) or is_atom(value)

  defp declared_attributes(effects) do
    Enum.reduce(effects, MapSet.new(), fn
      %Set{attribute: attribute}, declared -> MapSet.put(declared, attribute)
      %Where{effects: nested}, declared -> MapSet.union(declared, declared_attributes(nested))
      _push, declared -> declared
    end)
  end
end
