defmodule AshBackendDrivenOptimisticUi.ComparisonTest do
  use ExUnit.Case, async: true
  use AshBackendDrivenOptimisticUi.Test

  alias AshBackendDrivenOptimisticUi.TestSupport.ComparisonResource

  defp thing(attrs), do: ComparisonResource |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()

  describe "GIVEN a rule that compares texts or dates WHEN the real action runs" do
    test "THEN a text attribute compared with a text literal agrees with Ash" do
      assert optimistic(ComparisonResource, :text_before_m, thing(%{name: "anna"}), %{}).verdict == "yes"
      assert optimistic(ComparisonResource, :text_before_m, thing(%{name: "zed"}), %{}).verdict == "no"
    end

    test "THEN a date attribute compared with a date literal agrees with Ash" do
      assert optimistic(ComparisonResource, :born_before_2000, thing(%{born_on: ~D[1999-12-31]}), %{}).verdict == "yes"
      assert optimistic(ComparisonResource, :born_before_2000, thing(%{born_on: ~D[2000-01-02]}), %{}).verdict == "no"
    end

    test "THEN a date attribute compared with a date argument agrees with Ash" do
      record = thing(%{born_on: ~D[1999-12-31]})

      assert optimistic(ComparisonResource, :born_before_cutoff, record, %{cutoff: ~D[2000-01-01]}).verdict == "yes"
      assert optimistic(ComparisonResource, :born_before_cutoff, record, %{cutoff: ~D[1999-01-01]}).verdict == "no"
    end

    test "THEN a decimal attribute is still compared as a number" do
      assert optimistic(ComparisonResource, :amount_over_five, thing(%{amount: Decimal.new("10.5")}), %{}).verdict ==
               "yes"
    end
  end

  describe "GIVEN a rule that compares a nil value WHEN the real action runs" do
    test "THEN != against a nil attribute is false, as in Ash" do
      assert optimistic(ComparisonResource, :score_differs_from_five, thing(%{}), %{}).verdict == "no"
      assert optimistic(ComparisonResource, :score_differs_from_five, thing(%{score: 4}), %{}).verdict == "yes"
    end

    test "THEN == between two nil attributes is false, as in Ash" do
      assert optimistic(ComparisonResource, :score_equals_limit, thing(%{}), %{}).verdict == "no"
      assert optimistic(ComparisonResource, :score_equals_limit, thing(%{score: 3, limit: 3}), %{}).verdict == "yes"
    end

    test "THEN in against a nil attribute is false, as in Ash" do
      assert optimistic(ComparisonResource, :score_in_list, thing(%{}), %{}).verdict == "no"
      assert optimistic(ComparisonResource, :score_in_list, thing(%{score: 2}), %{}).verdict == "yes"
    end
  end
end
