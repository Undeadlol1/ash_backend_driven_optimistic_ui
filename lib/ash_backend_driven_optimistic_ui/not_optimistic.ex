defmodule AshBackendDrivenOptimisticUi.NotOptimistic do
  @moduledoc """
  Says an action deliberately has no `optimistic` rule, and why.

      not_optimistic :create_from_image, because: :ai_result

  The reason is one of `reasons/0`:

    * `:ai_result` - an AI or external service decides the answer.
    * `:server_decides` - random, server-computed, or depends on other users.
    * `:background` - telemetry, sync, fire-and-forget.
    * `:admin` - admin, dev, rare settings, auth.
    * `:not_yet` - should be optimistic, not converted yet.

  Nothing is shipped to the client; tooling reads it with
  `AshBackendDrivenOptimisticUi.Info.not_optimistic/1`.
  """

  alias Spark.Dsl.Entity

  @reasons [
    :ai_result,
    :server_decides,
    :background,
    :admin,
    :not_yet
  ]

  defstruct [:action, :because, :__identifier__, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          action: atom(),
          because: atom(),
          __identifier__: atom() | nil,
          __spark_metadata__: Entity.spark_meta()
        }

  @doc "The accepted `because:` values."
  @spec reasons() :: [atom()]
  def reasons, do: @reasons

  @doc false
  def __entity__ do
    %Entity{
      name: :not_optimistic,
      describe: "Opts a create, update, destroy or generic action out of optimistic UI, with a reason.",
      target: __MODULE__,
      args: [:action],
      schema: [
        action: [type: :atom, required: true, doc: "The action that has no `optimistic` rule."],
        because: [type: {:one_of, @reasons}, required: true, doc: "Why it has none."]
      ]
    }
  end
end
