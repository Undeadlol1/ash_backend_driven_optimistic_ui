defmodule AshBackendDrivenOptimisticUi.Effect.Where do
  @moduledoc "Applies the nested effects only when `condition` holds."

  alias AshBackendDrivenOptimisticUi.Effect.Push
  alias AshBackendDrivenOptimisticUi.Effect.Set
  alias Spark.Dsl.Entity

  defstruct [:condition, effects: [], __spark_metadata__: nil]

  @type t :: %__MODULE__{
          condition: term(),
          effects: [AshBackendDrivenOptimisticUi.Effect.t()],
          __spark_metadata__: Entity.spark_meta()
        }

  defp schema do
    [
      condition: [
        type: :any,
        required: true,
        doc: "An `expr(...)` that must be true for the nested effects to apply."
      ]
    ]
  end

  @doc false
  def __entity__ do
    %Entity{
      name: :where,
      describe: "Apply the nested effects only when the condition holds.",
      examples: ["where expr(arg(:xp_amount) >= xp_to_next_level) do ... end"],
      target: __MODULE__,
      args: [:condition],
      recursive_as: :effects,
      entities: [
        effects: [Set.__entity__(), Push.__entity__()]
      ],
      schema: schema()
    }
  end
end
