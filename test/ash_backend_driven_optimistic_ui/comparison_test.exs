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

    test "THEN a text attribute compared with a number literal compares as text, as Ash does" do
      assert optimistic(ComparisonResource, :name_over_five, thing(%{name: "10"}), %{}).verdict == "no"
      assert optimistic(ComparisonResource, :name_over_five, thing(%{name: "6"}), %{}).verdict == "yes"
    end

    test "THEN two text calculations compare as text" do
      record =
        ComparisonResource
        |> Ash.Changeset.for_create(:create, %{name: "a"})
        |> Ash.create!()
        |> Ash.load!([:shout, :whisper])

      assert optimistic(ComparisonResource, :shout_before_whisper, record, %{}).verdict == "yes"
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

  describe "GIVEN a rule that compares date-times of different precision WHEN the real action runs" do
    test "THEN a microsecond attribute equal to a second literal counts as equal" do
      assert optimistic(ComparisonResource, :at_from_2020, thing(%{at: ~U[2020-01-01 00:00:00Z]}), %{}).verdict == "yes"
      assert optimistic(ComparisonResource, :at_from_2020, thing(%{at: ~U[2019-12-31 23:59:59Z]}), %{}).verdict == "no"
    end

    test "THEN a second attribute equal to a literal counts as equal" do
      record = thing(%{at_sec: ~U[2020-01-01 00:00:00Z]})

      assert optimistic(ComparisonResource, :at_sec_from_2020, record, %{}).verdict == "yes"
    end

    test "THEN a microsecond attribute is compared with a microsecond argument and with now()" do
      record = thing(%{at: ~U[2020-01-01 00:00:00Z]})

      assert optimistic(ComparisonResource, :at_since, record, %{since: ~U[2020-01-01 00:00:00.000000Z]}).verdict ==
               "yes"

      assert optimistic(ComparisonResource, :at_before_now, record, %{}).verdict == "yes"
    end
  end

  describe "GIVEN a rule that compares a nil value WHEN the real action runs" do
    test "THEN > against a nil attribute is false, as in Ash" do
      assert optimistic(ComparisonResource, :score_over_five, thing(%{}), %{}).verdict == "no"
      assert optimistic(ComparisonResource, :score_over_five, thing(%{score: 6}), %{}).verdict == "yes"
    end

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
