defmodule AshBackendDrivenOptimisticUi.SnapshotTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Snapshot

  @moduletag :tmp_dir

  @rules %{
    "wallet.spend" => %{
      "effects" => [%{"set" => %{"b" => 1, "a" => 2}, "source" => "derived"}],
      "reactions" => []
    }
  }

  describe "GIVEN the rule snapshot" do
    test "WHEN a map is rendered THEN keys are sorted at every depth and the text ends with a newline" do
      rendered = Snapshot.render(%{"z" => 1, "a" => %{"y" => 2, "b" => 3}})

      assert rendered == ~s({\n  "a": {\n    "b": 3,\n    "y": 2\n  },\n  "z": 1\n}\n)
    end

    test "WHEN rules are written THEN one file is written per rule and files of removed rules are deleted",
         %{tmp_dir: dir} do
      File.write!(Snapshot.path(dir, "gone.rule"), "{}")

      assert Snapshot.write(@rules, dir) == %{written: ["wallet.spend"], removed: ["gone.rule"]}
      assert Snapshot.keys_on_disk(dir) == ["wallet.spend"]
    end

    test "WHEN the rules have just been written THEN there is no drift", %{tmp_dir: dir} do
      Snapshot.write(@rules, dir)

      assert Snapshot.drift(@rules, dir) == %{missing: [], changed: [], stale: []}
    end

    test "WHEN a rule is missing, a file is edited and an old file remains THEN drift names all three",
         %{tmp_dir: dir} do
      Snapshot.write(@rules, dir)
      File.write!(Snapshot.path(dir, "wallet.spend"), "{}")
      File.write!(Snapshot.path(dir, "old.rule"), "{}")
      rules = Map.put(@rules, "wallet.earn", %{})

      assert Snapshot.drift(rules, dir) == %{
               missing: ["wallet.earn"],
               changed: ["wallet.spend"],
               stale: ["old.rule"]
             }
    end

    test "WHEN no directory is given THEN the committed snapshot directory is used unless one is set" do
      assert Snapshot.dir() == "test/optimistic_ui/__snapshots__"
      assert Snapshot.dir(snapshot_dir: "elsewhere") == "elsewhere"
    end
  end
end
