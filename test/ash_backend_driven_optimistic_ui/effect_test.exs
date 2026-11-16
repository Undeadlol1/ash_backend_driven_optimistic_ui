defmodule AshBackendDrivenOptimisticUi.EffectTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Effect
  alias AshBackendDrivenOptimisticUi.Effect.Clear
  alias AshBackendDrivenOptimisticUi.Effect.Edit

  describe "GIVEN the nested list effects" do
    test "WHEN the rule entities are listed THEN they include the nested list effects" do
      names = Enum.map(Effect.__rule_entities__(), & &1.name)

      assert :clear in names and :edit in names
    end

    test "WHEN a nested list effect is built THEN it keeps its path in from" do
      assert %Clear{from: [:messages]} = struct(Clear, from: [:messages])
      assert Edit.__entity__().examples == ["edit from: [:meals, :ingredients]"]
    end

    test "WHEN a nested list effect is expanded THEN it is a struct with a required list path" do
      quote_result =
        quote(do: Effect.nested_list_effect(:empty, "Empty it.", "empty from: [:a]", "The list."))

      expansion =
        quote_result
        |> Macro.expand_once(%{__ENV__ | requires: [Effect | __ENV__.requires]})
        |> Macro.to_string()

      assert expansion =~ "defstruct [:from"
      assert expansion =~ "required: true"
    end
  end
end
