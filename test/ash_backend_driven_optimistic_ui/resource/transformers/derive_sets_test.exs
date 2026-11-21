defmodule AshBackendDrivenOptimisticUi.Resource.Transformers.DeriveSetsTest do
  use ExUnit.Case, async: true
  use AshBackendDrivenOptimisticUi.Test

  import AshBackendDrivenOptimisticUi.TestHelpers, only: [input: 1, record: 1]

  alias AshBackendDrivenOptimisticUi.Info
  alias AshBackendDrivenOptimisticUi.Resource.Transformers.DeriveSets
  alias AshBackendDrivenOptimisticUi.Rules
  alias AshBackendDrivenOptimisticUi.TestSupport.SampleResource
  alias AshBackendDrivenOptimisticUi.TestSupport.UpdateFieldsResource

  defp rule(action), do: Map.fetch!(Rules.for_resource(UpdateFieldsResource), "update_fields_resource.#{action}")

  defp has_title_then_set_title(source) do
    %{
      "where" => %{"has" => "input.title"},
      "effects" => [%{"set" => %{"title" => input(:title)}, "source" => source}]
    }
  end

  defp has_note_then_set_note do
    %{
      "where" => %{"has" => "input.note"},
      "effects" => [%{"set" => %{"note" => input(:note)}, "source" => "derived"}]
    }
  end

  defp sets(action, record, input),
    do: AshBackendDrivenOptimisticUi.Test.rules(UpdateFieldsResource, action, record, input).sets

  defp titled(attrs), do: UpdateFieldsResource |> Ash.Changeset.for_create(:make, attrs) |> Ash.create!()

  describe "GIVEN an update that accepts attributes WHEN the resource is transformed" do
    test "THEN every accepted attribute becomes a derived set applied only when the input carries it" do
      assert rule(:edit) == %{
               "effects" => [has_title_then_set_title("derived"), has_note_then_set_note()]
             }
    end

    test "THEN a field sent as nil is carried and the derived set writes nil" do
      record = titled(%{title: "old"})

      assert sets(:edit, record, %{title: nil}) == %{"title" => nil}
    end

    test "THEN a field that is not sent is left alone and the record keeps its value" do
      record = titled(%{title: "old"})

      assert sets(:edit, record, %{note: "n"}) == %{"note" => "n"}
      assert sets(:edit, record, %{}) == %{}
    end

    test "THEN an update with no accepted attributes derives nothing" do
      assert rule(:edit_nothing) == %{"effects" => []}
    end

    test "THEN an attribute set from an argument by a readable change is derived once, from the change" do
      assert rule(:edit_through_argument) == %{
               "effects" => [%{"set" => %{"title" => input(:label)}, "source" => "derived"}]
             }
    end

    test "THEN an accepted attribute that an atomic update also changes is derived once, from the change" do
      counts =
        for %{"set" => %{"count" => _} = set} <- rule(:edit_counting)["effects"], do: set

      assert counts == [%{"count" => %{"+" => [record(:count), 1]}}]
      assert length(rule(:edit_counting)["effects"]) == 2
    end

    test "THEN a declared set for an attribute replaces only that attribute's derived effect" do
      assert rule(:edit_declared_title) == %{
               "effects" => [
                 has_note_then_set_note(),
                 %{"set" => %{"title" => input(:title)}, "source" => "declared"}
               ]
             }
    end

    test "THEN a declared set inside a where drops the derived effect and stays inside its where" do
      assert rule(:edit_declared_in_where) == %{
               "effects" => [has_note_then_set_note(), has_title_then_set_title("declared")]
             }
    end

    test "THEN a create is unchanged and a destroy derives nothing from accept" do
      assert rule(:make) == %{
               "effects" => [%{"set" => %{"title" => input(:title)}, "source" => "derived"}]
             }

      assert rule(:remove_titled) == %{"effects" => [%{"remove" => %{}}]}
    end

    test "THEN a generic action derives nothing" do
      discard_all =
        Map.fetch!(
          Rules.for_resource(AshBackendDrivenOptimisticUi.TestSupport.ListItemResource),
          "list_item_resource.discard_all"
        )

      refute Enum.any?(discard_all["effects"], &(&1["source"] == "derived"))
    end
  end

  describe "GIVEN a derived update rule WHEN the real action runs" do
    test "THEN sending only some fields passes and the unsent field keeps its value" do
      record = titled(%{title: "old"})
      record = record |> Ash.Changeset.for_update(:edit, %{note: "first"}) |> Ash.update!()

      edited = optimistic(UpdateFieldsResource, :edit, record, %{title: "new"})

      assert edited.title == "new"
      assert edited.note == "first"
    end

    test "THEN a field sent as nil clears the real record too" do
      record = titled(%{title: "old"})

      assert optimistic(UpdateFieldsResource, :edit, record, %{title: nil}).title == nil
    end

    test "THEN a rule that disagrees with the real record fails" do
      record = titled(%{title: "old"})

      {_real, failures} =
        AshBackendDrivenOptimisticUi.Test.check_rule(
          UpdateFieldsResource,
          :edit_disagreeing,
          record,
          %{count: 5},
          []
        )

      assert [_ | _] = failures
    end

    test "THEN the explain task marks the derived sets inside their where" do
      text =
        Mix.Tasks.OptimisticUi.Explain.render(
          "update_fields_resource.edit",
          Map.put(rule(:edit), "reactions", [])
        )

      assert text =~
               ~s(  where {"has":"input.title"}\n    set title = {"var":"input.title"}  [derived])

      assert text =~
               ~s(  where {"has":"input.note"}\n    set note = {"var":"input.note"}  [derived])
    end
  end

  describe "GIVEN the derive sets transformer WHEN the resource is transformed" do
    test "THEN a readable change becomes a derived set placed before the declared effects" do
      award_xp_rule = Map.fetch!(Rules.for_resource(SampleResource), "sample_resource.award_xp")

      assert award_xp_rule == %{
               "effects" => [
                 %{
                   "set" => %{"total_xp" => %{"+" => [record(:total_xp), input(:xp_amount)]}},
                   "source" => "derived"
                 },
                 %{
                   "push" => %{
                     "event" => "xp_awarded",
                     "payload" => %{
                       "xp_amount" => input(:xp_amount),
                       "id" => %{"var" => "ctx.push_ids.xp_awarded.award_xp"}
                     }
                   }
                 },
                 %{
                   "where" => %{">=" => [%{"+" => [input(:xp_amount)]}, %{"+" => [record(:xp_to_next_level)]}]},
                   "effects" => [
                     %{
                       "set" => %{"current_level" => %{"+" => [record(:current_level), 1]}},
                       "source" => "declared"
                     },
                     %{
                       "push" => %{
                         "event" => "level_up",
                         "payload" => %{
                           "message" => %{"var" => "ctx.level_up_message"},
                           "id" => %{"var" => "ctx.push_ids.level_up.award_xp"}
                         }
                       }
                     }
                   ]
                 }
               ]
             }
    end

    test "THEN an explicit set overrides the derived one and an opaque change yields nothing" do
      spend_rule = Map.fetch!(Rules.for_resource(SampleResource), "sample_resource.spend")

      assert spend_rule == %{
               "effects" => [
                 %{"set" => %{"current_level" => 1}, "source" => "derived"},
                 %{
                   "set" => %{"balance" => %{"-" => [record(:balance), input(:cost)]}},
                   "source" => "declared"
                 }
               ]
             }
    end

    test "THEN a create derives a set for every accepted attribute unless a declared set claims it" do
      open_rule = Map.fetch!(Rules.for_resource(SampleResource), "sample_resource.open")

      assert open_rule == %{
               "effects" => [
                 %{"set" => %{"balance" => input(:balance)}, "source" => "derived"},
                 %{"set" => %{"current_level" => 1}, "source" => "declared"}
               ]
             }
    end

    test "THEN transforming an already derived resource again changes nothing" do
      dsl_state = SampleResource.spark_dsl_config()

      assert {:ok, transformed} = DeriveSets.transform(dsl_state)
      assert Info.rules(transformed) == Info.rules(dsl_state)
      assert DeriveSets.after?(Ash.Resource.Transformers.BelongsToAttribute)
    end
  end

  describe "GIVEN a set_attribute with options WHEN the resource is transformed" do
    test "THEN new?: true on an accepted attribute takes the sent value, else the given one" do
      for action <- [:make_untitled, :edit_untitled] do
        assert rule(action) == %{
                 "effects" => [
                   %{
                     "set" => %{
                       "title" => %{"if" => [%{"has" => "input.title"}, input(:title), "untitled"]}
                     },
                     "source" => "derived"
                   }
                 ]
               }
      end
    end

    test "THEN set_when_nil?: false applies only when the value is not nil" do
      assert rule(:edit_labelled) == %{
               "effects" => [
                 %{
                   "where" => %{"!" => [%{"==" => [input(:label), nil]}]},
                   "effects" => [%{"set" => %{"title" => input(:label)}, "source" => "derived"}]
                 }
               ]
             }
    end

    test "THEN set_when_nil?: false with a literal value needs no condition" do
      assert rule(:edit_labelled_literal) == %{
               "effects" => [%{"set" => %{"title" => "fixed"}, "source" => "derived"}]
             }
    end

    test "THEN a create takes the attribute's literal default when the input omits it" do
      assert rule(:make_with_default)["effects"] == [
               %{"set" => %{"title" => input(:title)}, "source" => "derived"},
               %{
                 "set" => %{"status" => %{"if" => [%{"has" => "input.status"}, input(:status), "open"]}},
                 "source" => "derived"
               }
             ]
    end

    test "THEN a create claims nothing for a default only the server can compute" do
      assert rule(:make_stamped)["effects"] == [
               %{"set" => %{"title" => input(:title)}, "source" => "derived"},
               %{
                 "where" => %{"has" => "input.stamp"},
                 "effects" => [%{"set" => %{"stamp" => input(:stamp)}, "source" => "derived"}]
               }
             ]
    end
  end

  describe "GIVEN a set_attribute with options WHEN the real action runs" do
    test "THEN new?: true keeps a sent value and fills an omitted one, on a create and an update" do
      assert optimistic(UpdateFieldsResource, :make_untitled, nil, %{title: "mine"}).title == "mine"
      assert optimistic(UpdateFieldsResource, :make_untitled, nil, %{}).title == "untitled"

      assert optimistic(UpdateFieldsResource, :edit_untitled, titled(%{title: "old"}), %{title: "mine"}).title == "mine"
      assert optimistic(UpdateFieldsResource, :edit_untitled, titled(%{title: "old"}), %{}).title == "untitled"
    end

    test "THEN set_when_nil?: false leaves the record alone when the value is nil" do
      record = titled(%{title: "old"})

      assert optimistic(UpdateFieldsResource, :edit_labelled, record, %{label: nil}).title == "old"
      assert optimistic(UpdateFieldsResource, :edit_labelled, record, %{label: "new"}).title == "new"
    end

    test "THEN a create without an accepted attribute gets its default, as the rule says" do
      assert optimistic(UpdateFieldsResource, :make_with_default, nil, %{title: "t"}).status == "open"
      assert optimistic(UpdateFieldsResource, :make_with_default, nil, %{title: "t", status: "done"}).status == "done"
    end

    test "THEN a create with a computed default passes whether or not the input carries it" do
      assert optimistic(UpdateFieldsResource, :make_stamped, nil, %{title: "t"}).stamp
      assert optimistic(UpdateFieldsResource, :make_stamped, nil, %{title: "t", stamp: ~U[2026-01-01 10:00:00Z]}).stamp
    end
  end
end
