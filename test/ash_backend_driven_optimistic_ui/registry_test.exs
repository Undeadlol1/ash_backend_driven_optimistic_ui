defmodule AshBackendDrivenOptimisticUi.RegistryTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Registry
  alias AshBackendDrivenOptimisticUi.TestSupport.CycleDomain
  alias AshBackendDrivenOptimisticUi.TestSupport.ListItemResource
  alias AshBackendDrivenOptimisticUi.TestSupport.SampleDomain
  alias AshBackendDrivenOptimisticUi.TestSupport.SampleResource

  defp reaction_pairs(rules, key), do: for(r <- rules["rules"][key]["reactions"], do: {r["on"], r["type"]})

  describe "GIVEN the optimistic UI registry" do
    test "WHEN rules are collected from every resource THEN each type and action has one merged key" do
      keys = [CycleDomain] |> Registry.rules() |> Map.fetch!("rules") |> Map.keys() |> Enum.sort()

      assert keys == [
               "sample_resource.award_xp",
               "sample_resource.close",
               "sample_resource.open",
               "sample_resource.refund",
               "sample_resource.spend",
               "sample_resource.tip"
             ]
    end

    test "WHEN a rule pushes an event that a reaction answers THEN the rule lists that reaction" do
      rules = Registry.rules([SampleDomain])

      assert rules["rules"]["sample_resource.award_xp"]["reactions"] == [
               %{
                 "on" => "level_up",
                 "type" => "sample_resource",
                 "effects" => [
                   %{
                     "set" => %{"balance" => %{"+" => [%{"var" => "record.balance"}, 1]}},
                     "source" => "declared"
                   }
                 ]
               }
             ]
    end

    test "WHEN a rule pushes only events that no resource answers THEN it has no reactions" do
      assert Registry.rules([SampleDomain])["rules"]["sample_resource.spend"]["reactions"] == []
    end

    test "WHEN reactions push each other's events THEN each runs once and the chain ends" do
      rules = Registry.rules([CycleDomain])

      assert reaction_pairs(rules, "sample_resource.award_xp") == [
               {"xp_awarded", "cycle_resource"},
               {"level_up", "sample_resource"},
               {"level_up", "cycle_resource"}
             ]
    end

    test "WHEN the set of rules changes THEN the version changes" do
      refute Registry.rules([SampleDomain])["version"] == Registry.rules([CycleDomain])["version"]
    end

    test "WHEN the version is read twice THEN it is sixteen hex characters and stays the same" do
      version = Registry.version()

      assert version =~ ~r/\A[0-9a-f]{16}\z/
      assert Registry.version() == version
    end

    test "WHEN the rule resources of a domain are listed THEN only resources that declare rules appear" do
      assert Registry.rule_resources([SampleDomain]) == [SampleResource, ListItemResource]
    end
  end
end
