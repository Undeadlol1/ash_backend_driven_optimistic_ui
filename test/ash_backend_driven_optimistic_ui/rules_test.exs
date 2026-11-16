defmodule AshBackendDrivenOptimisticUi.RulesTest do
  use ExUnit.Case, async: true

  import AshBackendDrivenOptimisticUi.TestHelpers, only: [record: 1]

  alias AshBackendDrivenOptimisticUi.Rules
  alias AshBackendDrivenOptimisticUi.TestSupport.CreatePushResource
  alias AshBackendDrivenOptimisticUi.TestSupport.ListItemResource
  alias AshBackendDrivenOptimisticUi.TestSupport.SampleResource
  alias AshBackendDrivenOptimisticUi.TestSupport.UncompilableResource

  defp all_effects(rules) do
    rules |> Map.values() |> Enum.flat_map(&flatten_effects(&1["effects"]))
  end

  defp flatten_effects(effects) do
    Enum.flat_map(effects, fn
      %{"effects" => nested} -> flatten_effects(nested)
      effect -> [effect]
    end)
  end

  describe "GIVEN the optimistic UI rules" do
    test "WHEN a resource's rules are collected THEN they are keyed by every optimistic action" do
      assert SampleResource |> Rules.for_resource() |> Map.keys() |> Enum.sort() ==
               [
                 "sample_resource.award_xp",
                 "sample_resource.close",
                 "sample_resource.open",
                 "sample_resource.refund",
                 "sample_resource.spend",
                 "sample_resource.tip"
               ]
    end

    test "WHEN a resource's reactions are collected THEN they are keyed by the event they answer" do
      assert Rules.reactions_for_resource(SampleResource) == %{
               "level_up" => [
                 %{
                   "set" => %{"balance" => %{"+" => [record(:balance), 1]}},
                   "source" => "declared"
                 }
               ],
               "tipped" => [
                 %{
                   "set" => %{
                     "balance" => %{"+" => [record(:balance), %{"var" => "event.amount"}]}
                   },
                   "source" => "declared"
                 },
                 %{
                   "push" => %{
                     "event" => "tip_received",
                     "payload" => %{
                       "amount" => %{"var" => "event.amount"},
                       "id" => %{"var" => "ctx.push_ids.tip_received.tipped"}
                     }
                   }
                 }
               ]
             }
    end

    test "WHEN an update rule pushes an event THEN its id is read from ctx.push_ids under the action name" do
      %{"effects" => effects} =
        SampleResource |> Rules.for_resource() |> Map.fetch!("sample_resource.tip")

      assert %{"push" => %{"event" => "tipped", "payload" => %{"id" => id}}} =
               Enum.find(effects, &Map.has_key?(&1, "push"))

      assert id == %{"var" => "ctx.push_ids.tipped.tip"}
    end

    test "WHEN a push is nested in a where THEN its id is read from ctx.push_ids too" do
      rule = SampleResource |> Rules.for_resource() |> Map.fetch!("sample_resource.award_xp")

      ids =
        for %{"push" => %{"event" => event, "payload" => %{"id" => id}}} <-
              flatten_effects(rule["effects"]),
            into: %{},
            do: {event, id}

      assert ids == %{
               "xp_awarded" => %{"var" => "ctx.push_ids.xp_awarded.award_xp"},
               "level_up" => %{"var" => "ctx.push_ids.level_up.award_xp"}
             }
    end

    test "WHEN a create rule pushes an event THEN the push has no id, since no record exists before the write" do
      pushes =
        for %{"push" => push} <- all_effects(Rules.for_resource(CreatePushResource)), do: push

      assert [%{"event" => "created"} = push] = pushes
      refute Map.has_key?(push["payload"], "id")
    end

    test "WHEN a create rule inserts into a list THEN the new record is built from its sets and inserted at the start" do
      assert ListItemResource |> Rules.for_resource() |> Map.fetch!("list_item_resource.add") ==
               %{
                 "effects" => [
                   %{"set" => %{"title" => %{"var" => "input.title"}}, "source" => "derived"},
                   %{"insert" => %{"at" => "start"}}
                 ]
               }
    end

    test "WHEN a destroy rule removes from a list THEN the record is taken out of the list" do
      assert ListItemResource |> Rules.for_resource() |> Map.fetch!("list_item_resource.discard") ==
               %{"effects" => [%{"remove" => %{}}]}
    end

    test "WHEN the type of a resource is read THEN it is the module's last segment, underscored" do
      assert Rules.type(SampleResource) == "sample_resource"
    end

    test "WHEN an expression the client cannot run is compiled THEN the error names the resource, the action and the node" do
      error = assert_raise ArgumentError, fn -> Rules.for_resource(UncompilableResource) end

      assert error.message =~ inspect(UncompilableResource)
      assert error.message =~ ":touch"
      assert error.message =~ "today"
    end

    test "WHEN a create rule inserts into a nested list THEN the insert names each step and the parent row it goes under" do
      %{"effects" => effects} =
        ListItemResource |> Rules.for_resource() |> Map.fetch!("list_item_resource.add_to_group")

      assert List.last(effects) == %{
               "insert" => %{
                 "at" => "end",
                 "into" => [
                   %{"key" => "groups", "match" => %{"id" => %{"var" => "input.group_id"}}},
                   %{"key" => "items"}
                 ]
               }
             }
    end

    test "WHEN a destroy rule removes from a nested list THEN the remove names the lists the row is looked for in" do
      assert ListItemResource
             |> Rules.for_resource()
             |> Map.fetch!("list_item_resource.discard_from_group") ==
               %{
                 "effects" => [
                   %{"remove" => %{"from" => [%{"key" => "groups"}, %{"key" => "items"}]}}
                 ]
               }
    end

    test "WHEN a create rule inserts into a sorted list THEN the insert names the field the list is ordered by" do
      %{"effects" => effects} =
        ListItemResource |> Rules.for_resource() |> Map.fetch!("list_item_resource.add_sorted")

      assert List.last(effects) == %{"insert" => %{"at" => %{"sorted_by" => "title"}}}
    end

    test "WHEN a rule clears nested lists THEN the clear names the lists it empties" do
      assert ListItemResource
             |> Rules.for_resource()
             |> Map.fetch!("list_item_resource.discard_all") ==
               %{
                 "effects" => [
                   %{"clear" => %{"from" => [%{"key" => "groups"}, %{"key" => "items"}]}}
                 ]
               }
    end

    test "WHEN an update rule edits a row in nested lists THEN the edit names the lists and has_arg guards a set" do
      assert ListItemResource
             |> Rules.for_resource()
             |> Map.fetch!("list_item_resource.retitle_in_group") ==
               %{
                 "effects" => [
                   %{"edit" => %{"from" => [%{"key" => "groups"}, %{"key" => "items"}]}},
                   %{
                     "where" => %{"has" => "input.title"},
                     "effects" => [
                       %{"set" => %{"title" => %{"var" => "input.title"}}, "source" => "declared"}
                     ]
                   }
                 ]
               }
    end

    test "WHEN a reaction has a where inside a where THEN each keeps its own condition and effects" do
      assert Rules.reactions_for_resource(ListItemResource) == %{
               "retitled" => [
                 %{
                   "where" => %{"==" => [record(:title), nil]},
                   "effects" => [
                     %{
                       "where" => %{"!=" => [%{"var" => "event.title"}, ""]},
                       "effects" => [
                         %{
                           "set" => %{"title" => %{"var" => "event.title"}},
                           "source" => "declared"
                         }
                       ]
                     }
                   ]
                 }
               ]
             }
    end
  end
end
