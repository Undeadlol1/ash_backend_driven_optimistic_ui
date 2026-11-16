defmodule AshBackendDrivenOptimisticUi.PushCollectorTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.PushCollector

  describe "GIVEN PushCollector" do
    test "WHEN a push is recorded without an open collector THEN record returns ok and drain is empty" do
      assert :ok = PushCollector.record("xp_awarded", %{"id" => "a"})
      assert PushCollector.drain() == []
    end

    test "WHEN pushes are recorded and drained THEN they come back in send order and later pushes are dropped" do
      PushCollector.open()
      PushCollector.record("xp_awarded", %{"id" => "a"})
      PushCollector.record("sync", %{"sync_cursor" => "1"})

      assert PushCollector.drain() == [
               %{"event" => "xp_awarded", "payload" => %{"id" => "a"}},
               %{"event" => "sync", "payload" => %{"sync_cursor" => "1"}}
             ]

      PushCollector.record("level_up", %{"id" => "b"})
      assert PushCollector.drain() == []
    end

    test "WHEN Ash runs the action in a task under a deadline THEN its pushes are collected in send order" do
      PushCollector.open()
      PushCollector.record("xp_awarded", %{"id" => "before"})

      Ash.ProcessHelpers.task_with_timeout(
        fn -> PushCollector.record("sync", %{"sync_cursor" => "in-task"}) end,
        AshBackendDrivenOptimisticUi.TestSupport.SampleResource,
        5_000,
        "action",
        nil
      )

      PushCollector.record("level_up", %{"id" => "after"})

      assert PushCollector.drain() == [
               %{"event" => "xp_awarded", "payload" => %{"id" => "before"}},
               %{"event" => "sync", "payload" => %{"sync_cursor" => "in-task"}},
               %{"event" => "level_up", "payload" => %{"id" => "after"}}
             ]
    end

    test "WHEN a task records after its caller drained THEN nothing reaches the caller" do
      PushCollector.open()
      PushCollector.drain()

      Task.await(Task.async(fn -> PushCollector.record("sync", %{"sync_cursor" => "late"}) end))

      PushCollector.open()
      assert PushCollector.drain() == []
    end
  end

  describe "GIVEN a request that sent optimistic ids" do
    test "WHEN nothing was pushed and no id was sent THEN there is nothing to reconcile" do
      PushCollector.open()

      assert PushCollector.drain_reconciliation([]) == nil
    end

    test "WHEN one sent id was pushed and one was not THEN the pushes come back and the other id is retracted" do
      PushCollector.open()
      PushCollector.record("xp_awarded", %{"id" => "happened"})

      assert PushCollector.drain_reconciliation(["happened, never-happened"]) == %{
               "pushes" => [%{"event" => "xp_awarded", "payload" => %{"id" => "happened"}}],
               "retracted" => ["never-happened"]
             }
    end

    test "WHEN a sent id matches a push's sync cursor THEN it is not retracted" do
      PushCollector.open()
      PushCollector.record("sync", %{sync_cursor: "cursor-1"})

      assert %{"retracted" => []} = PushCollector.drain_reconciliation(["cursor-1"])
    end

    test "WHEN the header name is asked for THEN it is x-optimistic-ids" do
      assert PushCollector.optimistic_ids_header() == "x-optimistic-ids"
    end
  end
end
