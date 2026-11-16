defmodule Mix.Tasks.OptimisticUi.SnapshotTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AshBackendDrivenOptimisticUi.Snapshot
  alias Mix.Tasks.OptimisticUi.Snapshot, as: SnapshotTask

  @moduletag :tmp_dir

  @rules %{"wallet.spend" => %{"effects" => [], "reactions" => []}}

  describe "GIVEN the optimistic UI snapshot task" do
    test "WHEN snapshots are out of date and update is off THEN it raises listing what is missing",
         %{tmp_dir: dir} do
      error = assert_raise Mix.Error, fn -> SnapshotTask.sync(@rules, dir, false) end

      assert error.message =~ "mix optimistic_ui.snapshot --update"
      assert error.message =~ "missing: wallet.spend"
    end

    test "WHEN snapshots match the rules and update is off THEN the check passes", %{tmp_dir: dir} do
      Snapshot.write(@rules, dir)

      assert SnapshotTask.sync(@rules, dir, false) == :ok
    end

    test "WHEN update is on THEN the rules are written and stale files are removed", %{
      tmp_dir: dir
    } do
      File.write!(Snapshot.path(dir, "gone.rule"), "{}")

      output = capture_io(fn -> SnapshotTask.sync(@rules, dir, true) end)

      assert Snapshot.keys_on_disk(dir) == ["wallet.spend"]
      assert output =~ "removed 1 stale"
    end

    test "WHEN run with a dir THEN the app's rules are checked against that dir", %{tmp_dir: dir} do
      Snapshot.write(AshBackendDrivenOptimisticUi.Registry.rules()["rules"], dir)

      assert SnapshotTask.run(["--dir", dir]) == :ok
    end
  end
end
