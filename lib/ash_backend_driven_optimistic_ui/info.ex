defmodule AshBackendDrivenOptimisticUi.Info do
  @moduledoc "Read a resource's `optimistic_ui do ... end` block."

  use Spark.InfoGenerator,
    extension: AshBackendDrivenOptimisticUi.Resource,
    sections: [:optimistic_ui]

  alias AshBackendDrivenOptimisticUi.NotOptimistic
  alias AshBackendDrivenOptimisticUi.Reaction
  alias AshBackendDrivenOptimisticUi.Rule
  alias Spark.Dsl.Extension

  @doc "The resource's `optimistic` entities, derived sets included."
  @spec rules(module() | map()) :: [Rule.t()]
  def rules(dsl_or_resource) do
    dsl_or_resource |> optimistic_ui() |> Enum.filter(&match?(%Rule{}, &1))
  end

  @doc "The resource's `on` entities."
  @spec reactions(module() | map()) :: [Reaction.t()]
  def reactions(dsl_or_resource) do
    dsl_or_resource
    |> Extension.get_entities([:optimistic_ui])
    |> Enum.filter(&match?(%Reaction{}, &1))
  end

  @doc "The resource's `not_optimistic` entities."
  @spec not_optimistic(module() | map()) :: [NotOptimistic.t()]
  def not_optimistic(dsl_or_resource) do
    dsl_or_resource
    |> Extension.get_entities([:optimistic_ui])
    |> Enum.filter(&match?(%NotOptimistic{}, &1))
  end
end
