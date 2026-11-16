defmodule AshBackendDrivenOptimisticUi.Effect.RemoveTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Effect.Remove
  alias AshBackendDrivenOptimisticUi.Info
  alias AshBackendDrivenOptimisticUi.TestSupport.ListItemResource

  describe "GIVEN the remove effect" do
    test "WHEN a destroy rule declares a remove THEN it is the rule's only effect" do
      [rule] = ListItemResource |> Info.rules() |> Enum.filter(&(&1.action == :discard))

      assert [%Remove{}] = rule.effects
    end
  end
end
