defmodule AshBackendDrivenOptimisticUi.Reaction do
  @moduledoc """
  This resource's effects when any resource's rule pushes `event`.
  Reactions see only this resource's record and the context, never action
  arguments.
  """

  alias Spark.Dsl.Entity

  defstruct [:event, :__identifier__, effects: [], __spark_metadata__: nil]

  @type t :: %__MODULE__{
          effects: [AshBackendDrivenOptimisticUi.Effect.t()],
          __identifier__: atom() | nil,
          event: atom(),
          __spark_metadata__: Entity.spark_meta()
        }

  defp schema do
    [
      event: [
        type: :atom,
        required: true,
        doc: "The pushed event this reaction answers, e.g. `:level_up`."
      ]
    ]
  end

  @doc false
  def __entity__ do
    %Entity{
      name: :on,
      describe: "This resource's effects when another resource's rule pushes the event.",
      target: __MODULE__,
      args: [:event],
      identifier: :event,
      imports: [Ash.Expr],
      entities: [effects: AshBackendDrivenOptimisticUi.Effect.__entities__()],
      schema: schema()
    }
  end
end
