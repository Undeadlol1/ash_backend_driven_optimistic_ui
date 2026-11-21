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
  The options of `set_attribute` are followed: `new?: true` on an accepted
  attribute takes the sent value, else the given one; `set_when_nil?: false`
  applies the set only when the value is not nil. A create gets, for an
  accepted attribute with a literal default, the sent value or else that
  default; for any other default (a function, say) it claims nothing unless
  the input carries the value.
  A destroy rule that declares no effect gets `remove()`.
  """

  use Spark.Dsl.Transformer

  alias Ash.Query.Call
  alias Ash.Query.Not
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
        from_changes = Enum.flat_map(changes, &derive(&1, action))
        undeclared = &Enum.reject(&1, fn set -> MapSet.member?(declared, attribute(set)) end)

        derived =
          action
          |> accepted_sets(dsl_state, from_changes)
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

  defp accepted_sets(%{type: type, accept: accept}, dsl_state, from_changes) when type in [:create, :update] do
    changed = MapSet.new(from_changes, &attribute/1)

    for attribute <- accept, not MapSet.member?(changed, attribute) do
      accepted_set(type, attribute, Info.attribute(dsl_state, attribute))
    end
  end

  defp accepted_sets(_action, _dsl_state, _from_changes), do: []

  # A create builds the record from the input, and an omitted attribute gets its default.
  defp accepted_set(:create, attribute, %{default: default}) when not is_nil(default) do
    if literal?(default),
      do: set(attribute, if_sent(attribute, default)),
      else: %Where{condition: sent(attribute), effects: [set(attribute, {:_arg, attribute})]}
  end

  defp accepted_set(_type, attribute, _attribute), do: set(attribute, {:_arg, attribute})

  defp set(attribute, value, from \\ nil), do: %Set{attribute: attribute, value: value, derived?: true, from: from}

  defp sent(attribute), do: %Call{name: :has_arg, args: [attribute]}

  defp if_sent(attribute, value), do: %Call{name: :if, args: [sent(attribute), {:_arg, attribute}, value]}

  defp attribute(%Set{attribute: attribute}), do: attribute
  defp attribute(%Where{effects: [set]}), do: attribute(set)

  defp derive(%Change{where: [], change: {Ash.Resource.Change.Atomic, opts}}, _action) do
    [set(opts[:attribute], opts[:expr])]
  end

  defp derive(%Change{where: [], change: {Ash.Resource.Change.SetAttribute, opts}}, action) do
    %{attribute: attribute, value: value} = Map.new(opts)

    cond do
      not readable_value?(value) -> []
      opts[:new?] -> [set(attribute, new_value(action, attribute, value))]
      opts[:set_when_nil?] == false and not literal?(value) -> [when_present(attribute, value)]
      true -> [set(attribute, value)]
    end
  end

  defp derive(%Change{where: [], change: {module, opts}}, _action) when is_atom(module) do
    Code.ensure_compiled!(module)

    if function_exported?(module, :optimistic_sets, 1) do
      for {attribute, value} <- module.optimistic_sets(opts),
          do: set(attribute, value, module)
    else
      []
    end
  end

  defp derive(_opaque_change, _action), do: []

  # `new?: true` keeps a value the input carries, so only an action that accepts the attribute can send one.
  defp new_value(%{accept: accept}, attribute, value) do
    if attribute in (accept || []), do: if_sent(attribute, value), else: value
  end

  defp when_present(attribute, value) do
    %Where{
      condition: %Not{expression: %Call{name: :is_nil, args: [value]}},
      effects: [set(attribute, value)]
    }
  end

  defp readable_value?({:_arg, _name}), do: true
  defp readable_value?(value), do: is_number(value) or is_binary(value) or is_atom(value)

  # A value the compiler writes out as it is: not nil, and nothing computed.
  defp literal?(value), do: is_number(value) or is_binary(value) or (is_atom(value) and value != nil)

  defp declared_attributes(effects) do
    Enum.reduce(effects, MapSet.new(), fn
      %Set{attribute: attribute}, declared -> MapSet.put(declared, attribute)
      %Where{effects: nested}, declared -> MapSet.union(declared, declared_attributes(nested))
      _push, declared -> declared
    end)
  end
end
