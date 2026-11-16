defmodule AshBackendDrivenOptimisticUi.ChangeTest do
  use ExUnit.Case, async: true
  use AshBackendDrivenOptimisticUi.Test

  import AshBackendDrivenOptimisticUi.TestHelpers, only: [input: 1, record: 1]

  alias AshBackendDrivenOptimisticUi.Rules
  alias AshBackendDrivenOptimisticUi.TestSupport.ChangeModuleResource
  alias AshBackendDrivenOptimisticUi.TestSupport.Clocked
  alias AshBackendDrivenOptimisticUi.TestSupport.FromOwner
  alias Spark.Error.DslError

  require Spark.Test

  defp rule(action), do: Map.fetch!(Rules.for_resource(ChangeModuleResource), "change_module_resource.#{action}")

  defp counted(count), do: ChangeModuleResource |> Ash.Changeset.for_create(:make, %{count: count}) |> Ash.create!()

  defp define_resource_using(change_module) do
    name = Module.concat(__MODULE__, "Resource#{System.unique_integer([:positive])}")

    body =
      quote do
        use Ash.Resource,
          domain: AshBackendDrivenOptimisticUi.TestSupport.UpdateFieldsDomain,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshBackendDrivenOptimisticUi.Resource]

        ets do
          private?(true)
        end

        optimistic_ui do
          optimistic(:touch)
        end

        actions do
          defaults([:read])

          update :touch do
            change(unquote(change_module))
          end
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:count, :integer, public?: true)
        end

        relationships do
          belongs_to(:owner, AshBackendDrivenOptimisticUi.TestSupport.SampleResource)
        end
      end

    Module.create(name, body, Macro.Env.location(__ENV__))
    name
  end

  describe "GIVEN a change module that describes its own effect WHEN the resource is transformed" do
    test "THEN its set is derived and compiled to JSON Logic" do
      assert rule(:bump) == %{
               "effects" => [
                 %{"set" => %{"count" => %{"+" => [record(:count), 2]}}, "source" => "derived"}
               ]
             }
    end

    test "THEN the opts the action passes reach the callback" do
      assert rule(:bump_by_five)["effects"] == [
               %{"set" => %{"count" => %{"+" => [record(:count), 5]}}, "source" => "derived"}
             ]
    end

    test "THEN a callback that returns a literal derives a literal set" do
      assert rule(:label) == %{
               "effects" => [%{"set" => %{"title" => "labelled"}, "source" => "derived"}]
             }
    end

    test "THEN a change without the callback derives nothing" do
      assert rule(:silent) == %{"effects" => []}
    end

    test "THEN a change guarded by where derives nothing" do
      assert rule(:guarded) == %{
               "effects" => [
                 %{
                   "where" => %{"has" => "input.note"},
                   "effects" => [%{"set" => %{"note" => input(:note)}, "source" => "derived"}]
                 }
               ]
             }
    end

    test "THEN a declared set for the same attribute replaces the derived one" do
      assert rule(:bump_declared) == %{
               "effects" => [
                 %{"set" => %{"count" => %{"+" => [record(:count), 100]}}, "source" => "declared"}
               ]
             }
    end

    test "THEN an accepted attribute the change also sets is derived once, from the change, on an update" do
      assert rule(:bump_accepting) == %{
               "effects" => [
                 %{"set" => %{"count" => %{"+" => [record(:count), 1]}}, "source" => "derived"}
               ]
             }
    end

    test "THEN an accepted attribute the change also sets is derived once, from the change, on a create" do
      assert rule(:make_bumped) == %{
               "effects" => [
                 %{"set" => %{"count" => %{"+" => [record(:count), 1]}}, "source" => "derived"}
               ]
             }
    end
  end

  describe "GIVEN a change module whose description the client cannot use WHEN the resource is compiled" do
    test "THEN a relationship fails compilation and the message names the change module" do
      errors =
        Spark.Test.dsl_errors do
          define_resource_using(FromOwner)
        end

      assert [{_resource, [%DslError{message: message}]}] = errors
      assert message =~ inspect(FromOwner)
      assert message =~ "relationships"
    end

    test "THEN an unsupported function fails and the message names the change module" do
      resource = define_resource_using(Clocked)

      error = assert_raise ArgumentError, fn -> Rules.for_resource(resource) end

      assert error.message =~ inspect(Clocked)
      assert error.message =~ "today"
    end
  end

  describe "GIVEN a derived change set WHEN the real action runs" do
    test "THEN the real record matches the rule" do
      record = counted(10)

      assert optimistic(ChangeModuleResource, :bump, record, %{}).count == 12
    end

    test "THEN a change whose description disagrees with what it does fails" do
      record = counted(10)

      {_real, failures} =
        AshBackendDrivenOptimisticUi.Test.check_rule(ChangeModuleResource, :liar, record, %{}, [])

      assert [_ | _] = failures
    end
  end

  describe "GIVEN the explain task WHEN a rule with a change set is rendered" do
    test "THEN the set is marked derived" do
      text =
        Mix.Tasks.OptimisticUi.Explain.render(
          "change_module_resource.bump",
          Map.put(rule(:bump), "reactions", [])
        )

      assert text =~ ~s(set count = {"+":[{"var":"record.count"},2]}  [derived])
    end
  end
end
