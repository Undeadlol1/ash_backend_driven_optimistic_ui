defmodule AshBackendDrivenOptimisticUi.Effect.ClearTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Effect.Clear
  alias AshBackendDrivenOptimisticUi.Info
  alias AshBackendDrivenOptimisticUi.TestSupport.ListItemResource

  describe "GIVEN the clear effect" do
    test "WHEN a clear rule is built THEN it keeps the path of the list it empties" do
      [rule] = ListItemResource |> Info.rules() |> Enum.filter(&(&1.action == :discard_all))

      assert [%Clear{from: [:groups, :items]}] = rule.effects
    end

    test "WHEN a clear names no list THEN the list path is required" do
      assert Clear.__entity__().schema[:from][:required]
    end
  end
end
