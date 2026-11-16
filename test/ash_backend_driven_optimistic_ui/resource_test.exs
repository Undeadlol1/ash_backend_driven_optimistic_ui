defmodule AshBackendDrivenOptimisticUi.ResourceTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Effect
  alias AshBackendDrivenOptimisticUi.NotOptimistic
  alias AshBackendDrivenOptimisticUi.Reaction
  alias AshBackendDrivenOptimisticUi.Rule

  describe "GIVEN the optimistic UI resource section" do
    test "WHEN the resource sections are read THEN the rules section is built from the optimistic, on and not_optimistic entities" do
      assert [%Spark.Dsl.Section{name: :optimistic_ui, entities: entities}] =
               AshBackendDrivenOptimisticUi.Resource.sections()

      assert Enum.map(entities, & &1.name) == [
               Rule.__entity__().name,
               Reaction.__entity__().name,
               NotOptimistic.__entity__().name
             ]
    end

    test "WHEN the effect entities are listed THEN where nests its own effects alongside set and push" do
      assert Enum.map(Effect.__entities__(), & &1.name) == [:set, :push, :where]

      assert [%{recursive_as: :effects, entities: [effects: [%{name: :set}, %{name: :push}]]}] =
               Enum.filter(Effect.__entities__(), &(&1.name == :where))
    end
  end
end
