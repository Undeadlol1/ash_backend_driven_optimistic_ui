defmodule AshBackendDrivenOptimisticUi.SnapshotStaleTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Registry
  alias AshBackendDrivenOptimisticUi.Snapshot

  @snapshot_dir "test/ash_backend_driven_optimistic_ui/__snapshots__"

  test "every file in the snapshot directory names a rule that exists" do
    rules = Registry.rules()["rules"]

    assert Snapshot.keys_on_disk(@snapshot_dir) -- Map.keys(rules) == []
  end

  test "every rule of the library's sample domain has its snapshot, unchanged" do
    assert %{missing: [], changed: []} = Snapshot.drift(Registry.rules()["rules"], @snapshot_dir)
  end
end
