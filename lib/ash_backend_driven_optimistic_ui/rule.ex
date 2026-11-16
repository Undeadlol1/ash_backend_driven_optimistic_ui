defmodule AshBackendDrivenOptimisticUi.Rule do
  @moduledoc """
  What the client may show the moment it calls `action`, before the server
  answers. Derived sets come first in `effects`, then the declared ones in
  order.
  """

  alias Spark.Dsl.Entity

  defstruct [:action, :__identifier__, effects: [], __spark_metadata__: nil]

  @type t :: %__MODULE__{
          action: atom(),
          effects: [AshBackendDrivenOptimisticUi.Effect.t()],
          __identifier__: atom() | nil,
          __spark_metadata__: Entity.spark_meta()
        }

  defp schema do
    [
      action: [
        type: :atom,
        required: true,
        doc: "A create, update, destroy or generic action on this resource."
      ]
    ]
  end

  @doc false
  def __entity__ do
    %Entity{
      name: :optimistic,
      describe: "The client-side effects of calling a create, update, destroy or generic action.",
      target: __MODULE__,
      args: [:action],
      identifier: :action,
      imports: [Ash.Expr],
      entities: [effects: AshBackendDrivenOptimisticUi.Effect.__rule_entities__()],
      schema: schema()
    }
  end
end
