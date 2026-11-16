defmodule AshBackendDrivenOptimisticUi.Effect.Set do
  @moduledoc """
  Sets one of the declaring resource's own attributes to the value of an
  expression. `derived?` marks a set read from the action's own changes
  rather than written in the `optimistic_ui` block. `from` is the change
  module it was read from, when it came from one.
  """

  alias Spark.Dsl.Entity

  defstruct [:attribute, :value, :from, derived?: false, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          attribute: atom(),
          value: term(),
          derived?: boolean(),
          from: module() | nil,
          __spark_metadata__: Entity.spark_meta()
        }

  defp schema do
    [
      attribute: [
        type: :atom,
        required: true,
        doc: "An attribute of this resource."
      ],
      value: [
        type: :any,
        required: true,
        doc: "An `expr(...)`, an `arg(...)` or a literal."
      ]
    ]
  end

  @doc false
  def __entity__ do
    %Entity{
      name: :set,
      describe: "Set one of this resource's attributes.",
      examples: ["set :current_level, expr(current_level + 1)"],
      target: __MODULE__,
      args: [:attribute, :value],
      imports: [Ash.Expr],
      schema: schema()
    }
  end
end
