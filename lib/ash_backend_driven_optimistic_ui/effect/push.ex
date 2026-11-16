defmodule AshBackendDrivenOptimisticUi.Effect.Push do
  @moduledoc """
  Plays a websocket push on the client, the same event the server's notifier
  sends, with a payload of expressions or literals.
  """

  alias Spark.Dsl.Entity

  defstruct [:event, payload: [], __spark_metadata__: nil]

  @type t :: %__MODULE__{
          event: atom(),
          payload: keyword(),
          __spark_metadata__: Entity.spark_meta()
        }

  defp schema do
    [
      event: [
        type: :atom,
        required: true,
        doc: "The push event name, e.g. `:xp_awarded`."
      ],
      payload: [
        type: :keyword_list,
        default: [],
        doc: "Payload fields as `key: expr(...)` or `key: literal` pairs."
      ]
    ]
  end

  @doc false
  def __entity__ do
    %Entity{
      name: :push,
      describe: "Play a websocket push on the client.",
      examples: ["push :xp_awarded, xp_amount: expr(arg(:xp_amount))"],
      target: __MODULE__,
      args: [:event, {:optional, :payload, []}],
      imports: [Ash.Expr],
      schema: schema()
    }
  end
end
