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

  describe "GIVEN a domain listed twice" do
    test "WHEN the rules are collected THEN each resource counts once and nothing raises" do
      assert Registry.rules([SampleDomain, SampleDomain]) == Registry.rules([SampleDomain])
    end
  end

  describe "GIVEN two resources whose rules get the same key" do
    test "WHEN the rules are collected THEN it raises naming both resources, the key and the way out" do
      suffix = System.unique_integer([:positive])
      first = Module.concat([__MODULE__, "First#{suffix}", Item])
      second = Module.concat([__MODULE__, "Second#{suffix}", Item])
      domain = Module.concat(__MODULE__, "Domain#{suffix}")

      for resource <- [first, second] do
        Module.create(
          resource,
          quote do
            use Ash.Resource,
              domain: SampleDomain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshBackendDrivenOptimisticUi.Resource]

            optimistic_ui do
              optimistic :open do
                set :balance, 1
              end
            end

            actions do
              defaults [:read]
              update :open
            end

            attributes do
              uuid_primary_key :id
              attribute :balance, :integer, public?: true
            end
          end,
          Macro.Env.location(__ENV__)
        )
      end

      Module.create(
        domain,
        quote do
          use Ash.Domain, validate_config_inclusion?: false

          resources do
            allow_unregistered? true
            resource unquote(first)
            resource unquote(second)
          end
        end,
        Macro.Env.location(__ENV__)
      )

      error = assert_raise ArgumentError, fn -> Registry.rules([domain]) end

      assert error.message =~ inspect(first)
      assert error.message =~ inspect(second)
      assert error.message =~ ~s("item.open")
      assert error.message =~ "different type names"
      assert error.message =~ "JSON:API type"
    end
  end
end
