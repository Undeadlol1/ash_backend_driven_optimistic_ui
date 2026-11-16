defmodule AshBackendDrivenOptimisticUi.PushIdTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.PushId
  alias AshBackendDrivenOptimisticUi.TestSupport.CreatePushResource
  alias AshBackendDrivenOptimisticUi.TestSupport.SampleResource

  @updated_at ~U[2026-10-25 18:03:00.123456Z]

  defp sample(attributes \\ []) do
    struct!(SampleResource, Keyword.merge([id: "42", updated_at: @updated_at], attributes))
  end

  describe "GIVEN the optimistic UI push id WHEN one push's id is built" do
    test "THEN the id is the type, record id, updated_at, event and label joined by colons" do
      assert PushId.for(sample(), :xp_awarded, :increment) ==
               "sample_resource:42:2026-10-25T18:03:00.123456Z:xp_awarded:increment"
    end

    test "THEN the id changes once the record has been written again" do
      written_again = sample(updated_at: DateTime.add(@updated_at, 1, :microsecond))

      refute PushId.for(sample(), :xp_awarded, :increment) ==
               PushId.for(written_again, :xp_awarded, :increment)
    end

    test "THEN the id differs per event and per label" do
      ids = [
        PushId.for(sample(), :xp_awarded, :increment),
        PushId.for(sample(), :level_up, :increment),
        PushId.for(sample(), :xp_awarded, :milestone)
      ]

      assert length(Enum.uniq(ids)) == 3
    end
  end

  describe "GIVEN the optimistic UI push id WHEN one push's id is built at an edge" do
    test "THEN six fractional digits are kept when the microseconds are zero" do
      on_the_second = sample(updated_at: ~U[2026-10-25 18:03:00.000000Z])

      assert PushId.for(on_the_second, :xp_awarded, :increment) ==
               "sample_resource:42:2026-10-25T18:03:00.000000Z:xp_awarded:increment"
    end

    test "THEN two records written at the same instant get different ids" do
      refute PushId.for(sample(id: "42"), :xp_awarded, :increment) ==
               PushId.for(sample(id: "43"), :xp_awarded, :increment)
    end

    test "THEN a record without updated_at raises rather than sharing an id" do
      assert_raise FunctionClauseError, fn ->
        PushId.for(sample(updated_at: nil), :xp_awarded, :increment)
      end
    end

    test "THEN each of fifty successive writes to one record gets a new id" do
      ids =
        for write <- 0..49 do
          written = sample(updated_at: DateTime.add(@updated_at, write, :microsecond))
          PushId.for(written, :xp_awarded, :increment)
        end

      assert length(Enum.uniq(ids)) == 50
    end
  end

  describe "GIVEN the optimistic UI push id WHEN the pushes a resource declares are listed" do
    test "THEN every push of an update or destroy rule is listed under the action name" do
      declared = PushId.declared(SampleResource)

      assert {:xp_awarded, :award_xp} in declared
      assert {:level_up, :award_xp} in declared
      assert {:closed, :close} in declared
    end

    test "THEN pushes of a reaction are listed under the event name they answer" do
      assert {:tip_received, :tipped} in PushId.declared(SampleResource)
    end

    test "THEN pushes of a create rule are left out, since no record exists before the write" do
      refute Enum.any?(PushId.declared(SampleResource), fn {_event, label} -> label == :open end)
    end
  end

  describe "GIVEN the optimistic UI push id WHEN the ids of one record are built" do
    test "THEN the ids are nested by event and label" do
      push_ids = PushId.for_record(sample())

      assert push_ids.xp_awarded.award_xp == PushId.for(sample(), :xp_awarded, :award_xp)
      assert push_ids.tip_received.tipped == PushId.for(sample(), :tip_received, :tipped)
    end
  end

  describe "GIVEN the optimistic UI push id WHEN the ids of a resource's record are built at an edge" do
    test "THEN a resource whose only push is made by a create rule has no ids" do
      push_ids = PushId.for_record(struct!(CreatePushResource, id: "7", updated_at: @updated_at))

      assert push_ids == %{}
    end

    test "THEN there is one id for every push the resource declares" do
      held = sample() |> PushId.for_record() |> Map.values() |> Enum.flat_map(&Map.values/1)

      assert length(held) == length(PushId.declared(SampleResource))
    end
  end

  describe "GIVEN the optimistic UI push id WHEN the path a compiled rule reads an id from is built" do
    test "THEN the path is the one the compiled push id reads from ctx" do
      assert PushId.variable(:xp_awarded, :increment) == "ctx.push_ids.xp_awarded.increment"
    end
  end

  describe "GIVEN the optimistic UI push id WHEN the actions that carry an id are checked" do
    test "THEN an update action carries an id and a create action does not" do
      assert PushId.identified?(SampleResource, :award_xp)
      refute PushId.identified?(SampleResource, :open)
    end
  end
end
