defmodule AshBackendDrivenOptimisticUi.Effect.EditTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Effect.Edit
  alias AshBackendDrivenOptimisticUi.Info
  alias AshBackendDrivenOptimisticUi.TestSupport.ListItemResource

  describe "GIVEN the edit effect" do
    test "WHEN an edit rule is built THEN it keeps the path of the list its row is in" do
      [rule] = ListItemResource |> Info.rules() |> Enum.filter(&(&1.action == :retitle_in_group))

      assert [%Edit{from: [:groups, :items]} | _guarded_sets] = rule.effects
    end

    test "WHEN an edit names no list THEN the list path is required" do
      assert Edit.__entity__().schema[:from][:required]
    end
  end
end
