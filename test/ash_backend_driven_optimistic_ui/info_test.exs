defmodule AshBackendDrivenOptimisticUi.InfoTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Effect.Push
  alias AshBackendDrivenOptimisticUi.Effect.Set
  alias AshBackendDrivenOptimisticUi.Effect.Where
  alias AshBackendDrivenOptimisticUi.Info
  alias AshBackendDrivenOptimisticUi.NotOptimistic
  alias AshBackendDrivenOptimisticUi.Reaction
  alias AshBackendDrivenOptimisticUi.Rule
  alias AshBackendDrivenOptimisticUi.TestSupport.SampleResource

  describe "GIVEN the optimistic UI info" do
    test "WHEN the rules of a resource are listed THEN optimistic entities come back with derived sets merged in" do
      assert [
               %Rule{
                 action: :award_xp,
                 effects: [
                   %Set{attribute: :total_xp, derived?: true},
                   %Push{event: :xp_awarded},
                   %Where{effects: [%Set{derived?: false}, %Push{event: :level_up}]}
                 ]
               },
               %Rule{action: :spend},
               %Rule{action: :refund},
               %Rule{
                 action: :open,
                 effects: [
                   %Set{attribute: :balance, derived?: true},
                   %Set{attribute: :current_level, derived?: false}
                 ]
               },
               %Rule{action: :tip},
               %Rule{action: :close, effects: [%Push{event: :closed}]}
             ] = Info.rules(SampleResource)
    end

    test "WHEN the reactions of a resource are listed THEN each reaction lists its effects" do
      assert [
               %Reaction{event: :level_up, effects: [%Set{attribute: :balance}]},
               %Reaction{
                 event: :tipped,
                 effects: [%Set{attribute: :balance}, %Push{event: :tip_received}]
               }
             ] = Info.reactions(SampleResource)
    end

    test "WHEN the opt-outs are listed THEN not_optimistic lists them and rules leaves them out" do
      assert [%NotOptimistic{action: :create, because: :admin}] =
               Info.not_optimistic(SampleResource)

      refute Enum.any?(Info.rules(SampleResource), &(&1.action == :create))
    end
  end
end
