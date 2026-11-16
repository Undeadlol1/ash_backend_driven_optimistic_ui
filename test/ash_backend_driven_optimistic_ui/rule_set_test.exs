defmodule AshBackendDrivenOptimisticUi.RuleSetTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.Registry
  alias AshBackendDrivenOptimisticUi.RuleSet
  alias AshBackendDrivenOptimisticUi.TestSupport.SampleDomain

  describe "GIVEN the rule set resource listed in a domain" do
    test "WHEN its rules action runs through the domain THEN it returns the registry rules" do
      assert {:ok, rules} =
               RuleSet
               |> Ash.ActionInput.for_action(:rules, %{}, domain: SampleDomain)
               |> Ash.run_action()

      assert rules == Registry.rules()
    end

    test "WHEN the rule resources of that domain are listed THEN the rule set is not one of them" do
      refute RuleSet in Registry.rule_resources([SampleDomain])
    end
  end
end
