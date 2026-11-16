defmodule AshBackendDrivenOptimisticUi.Effect.Insert do
  @moduledoc """
  Puts the record a create makes, built from the rule's sets, into the list
  the client holds of this resource, at its start or end, or, with
  `at: {:sorted_by, field}`, before the first row whose `field` sorts after
  its own, for a list the server orders by that field. The client gives it a
  temporary id that the saved record replaces.

  With `into:`, that list sits inside the one record the client holds:
  `into: [:workout, {:exercises, workout_exercise_id: expr(arg(:workout_exercise_id))}, :sets]`.
  """

  alias Spark.Dsl.Entity

  defstruct [:at, :into, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          at: :start | :end | {:sorted_by, atom()},
          into: AshBackendDrivenOptimisticUi.Effect.nested_path() | nil,
          __spark_metadata__: Entity.spark_meta()
        }

  @doc false
  def __entity__ do
    %Entity{
      name: :insert,
      describe: "Put the new record into the client's list of this resource.",
      examples: [
        "insert at: :start",
        "insert at: {:sorted_by, :name}",
        "insert at: :end, into: [{:groups, id: expr(arg(:group_id))}, :items]"
      ],
      target: __MODULE__,
      schema: [
        at: [
          type: {:or, [{:one_of, [:start, :end]}, {:tuple, [{:literal, :sorted_by}, :atom]}]},
          required: true,
          doc: "Where the list shows a new row: `:start`, `:end` or `{:sorted_by, field}`."
        ],
        into: [
          type: {:list, :any},
          doc:
            "A list nested inside the one record the client holds, as keys from its top: " <>
              "`{key, field: expr(...)}` steps into the rows of `key` whose `field` equals the value."
        ]
      ]
    }
  end
end
