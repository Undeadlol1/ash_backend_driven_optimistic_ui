defmodule Mix.Tasks.OptimisticUi.ExplainTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Registry
  alias AshBackendDrivenOptimisticUi.TestSupport.SampleDomain
  alias Mix.Tasks.OptimisticUi.Explain

  setup do
    {:ok, rule: Registry.rules([SampleDomain])["rules"]["sample_resource.award_xp"]}
  end

  describe "GIVEN the optimistic UI explain task" do
    test "WHEN a rule is rendered THEN each set is marked derived or declared", %{rule: rule} do
      text = Explain.render("sample_resource.award_xp", rule)

      assert text =~
               ~s(set total_xp = {"+":[{"var":"record.total_xp"},{"var":"input.xp_amount"}]}  [derived])

      assert text =~
               ~s(    set current_level = {"+":[{"var":"record.current_level"},1]}  [declared])
    end

    test "WHEN a rule with a where clause is rendered THEN its effects are nested under the where and pushes are printed",
         %{rule: rule} do
      text = Explain.render("sample_resource.award_xp", rule)

      assert text =~
               ~s(  push xp_awarded {"id":{"var":"ctx.push_ids.xp_awarded.award_xp"},"xp_amount":{"var":"input.xp_amount"}})

      assert text =~
               ~s(  where {">=":[{"+":[{"var":"input.xp_amount"}]},{"+":[{"var":"record.xp_to_next_level"}]}]}\n    set)
    end

    test "WHEN a rule with reactions is rendered THEN the reactions are listed after the effects",
         %{rule: rule} do
      text = Explain.render("sample_resource.award_xp", rule)

      assert text =~ "on level_up (sample_resource)\n  set balance"
    end

    test "WHEN a list rule is rendered THEN inserts and removes are printed" do
      rules = Registry.rules([SampleDomain])["rules"]

      assert Explain.render("list_item_resource.add", rules["list_item_resource.add"]) =~
               "\n  insert at start"

      assert Explain.render("list_item_resource.discard", rules["list_item_resource.discard"]) =~
               "\n  remove"
    end

    test "WHEN a nested list rule is rendered THEN the path of an insert or remove is printed" do
      rules = Registry.rules([SampleDomain])["rules"]

      assert Explain.render(
               "list_item_resource.add_to_group",
               rules["list_item_resource.add_to_group"]
             ) =~
               ~s(\n  insert at end into groups[id = {"var":"input.group_id"}].items)

      assert Explain.render(
               "list_item_resource.discard_from_group",
               rules["list_item_resource.discard_from_group"]
             ) =~
               "\n  remove from groups.items"
    end

    test "WHEN a sorted insert or a clear is rendered THEN they are printed" do
      rules = Registry.rules([SampleDomain])["rules"]

      assert Explain.render(
               "list_item_resource.add_sorted",
               rules["list_item_resource.add_sorted"]
             ) =~
               "\n  insert sorted by title"

      assert Explain.render(
               "list_item_resource.discard_all",
               rules["list_item_resource.discard_all"]
             ) =~
               "\n  clear from groups.items"
    end

    test "WHEN an edit of a nested row is rendered THEN it is printed" do
      rules = Registry.rules([SampleDomain])["rules"]

      assert Explain.render(
               "list_item_resource.retitle_in_group",
               rules["list_item_resource.retitle_in_group"]
             ) =~
               "\n  edit from groups.items"
    end

    test "WHEN one rule key is given THEN that rule is printed" do
      text = ExUnit.CaptureIO.capture_io(fn -> Explain.run(["sample_resource.award_xp"]) end)

      assert text =~ "sample_resource.award_xp"
    end

    test "WHEN no rule key is given THEN it raises with a usage message" do
      assert_raise Mix.Error, ~r/Usage: mix optimistic_ui.explain/, fn -> Explain.run([]) end
    end

    test "WHEN the rule key is unknown THEN it raises naming that rule" do
      assert_raise Mix.Error, ~r/No rule nope.nope/, fn -> Explain.run(["nope.nope"]) end
    end
  end
end
