defmodule AshBackendDrivenOptimisticUi.Effect.InsertTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Effect.Insert
  alias AshBackendDrivenOptimisticUi.Info
  alias AshBackendDrivenOptimisticUi.TestSupport.ListItemResource

  describe "GIVEN the insert effect" do
    test "WHEN a create rule declares an insert THEN it keeps where the list shows the new row" do
      [rule] = ListItemResource |> Info.rules() |> Enum.filter(&(&1.action == :add))

      assert [%Insert{at: :start}] = Enum.filter(rule.effects, &match?(%Insert{}, &1))
    end

    test "WHEN an insert is declared THEN it must say where the new row goes" do
      assert Insert.__entity__().schema[:at][:required]
    end
  end
end
