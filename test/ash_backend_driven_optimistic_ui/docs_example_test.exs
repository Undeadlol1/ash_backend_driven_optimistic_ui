defmodule AshBackendDrivenOptimisticUi.DocsExampleTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.PushId
  alias AshBackendDrivenOptimisticUi.Registry
  alias AshBackendDrivenOptimisticUi.TestSupport.Docs

  describe "GIVEN the todo app from How it works" do
    test "WHEN the list rule is collected THEN it is the JSON the README shows" do
      rule = Registry.rules([Docs.Domain])["rules"]["todo.create"]

      assert rule == %{
               "effects" => [
                 %{"set" => %{"title" => %{"var" => "input.title"}}, "source" => "derived"},
                 %{"insert" => %{"at" => "end"}}
               ],
               "reactions" => []
             }
    end

    test "WHEN its rules are collected THEN they are the JSON the guide shows" do
      rule = Registry.rules([Docs.Domain])["rules"]["todo.complete"]

      assert rule == %{
               "effects" => [
                 %{
                   "where" => %{"!" => [%{"var" => "record.done"}]},
                   "effects" => [
                     %{"set" => %{"done" => true}, "source" => "declared"},
                     %{
                       "push" => %{
                         "event" => "xp_awarded",
                         "payload" => %{
                           "amount" => 10,
                           "id" => %{"var" => "ctx.push_ids.xp_awarded.complete"}
                         }
                       }
                     }
                   ]
                 }
               ],
               "reactions" => [
                 %{
                   "on" => "xp_awarded",
                   "type" => "user_level",
                   "effects" => [
                     %{
                       "set" => %{
                         "total_xp" => %{
                           "+" => [%{"var" => "record.total_xp"}, %{"var" => "event.amount"}]
                         }
                       },
                       "source" => "declared"
                     }
                   ]
                 }
               ]
             }
    end

    test "WHEN a todo's push ids are computed THEN they have the guide's shape" do
      todo = %Docs.Todo{id: "42", updated_at: ~U[2026-10-25 18:03:00.123456Z]}

      assert PushId.for_record(todo) == %{
               xp_awarded: %{complete: "todo:42:2026-10-25T18:03:00.123456Z:xp_awarded:complete"}
             }
    end
  end
end
