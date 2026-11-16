defmodule AshBackendDrivenOptimisticUi.Resource do
  @moduledoc """
  Declare, next to an action, what the client may show the moment the user
  calls it, before the server answers.

      optimistic_ui do
        optimistic :award_xp do
          push :xp_awarded, xp_amount: expr(arg(:xp_amount))

          where expr(arg(:xp_amount) >= xp_to_next_level) do
            set :current_level, expr(current_level + 1)
            push :level_up, message: expr(^context(:level_up_message))
          end
        end

        on :level_up do
          set :balance, expr(balance + 1)
        end
      end

  An action that should have no rule says so with
  `not_optimistic :create_from_image, because: :ai_result`. The reason must be
  one of `AshBackendDrivenOptimisticUi.NotOptimistic.reasons/0`; the client never sees it.

  Readable changes on the action become `set` effects by themselves, ahead of
  the declared ones: `atomic_update(attr, expr)` and `set_attribute(attr, v)`
  where `v` is a literal or `arg(...)`. Opaque change modules and conditional
  changes yield nothing. A declared `set` for the same attribute, anywhere in
  the `optimistic`, replaces the derived one.

  An expression may read the record's own attributes, calculations and aggregates, the action's
  arguments (`arg/1`, not inside `on`), the context (`^context/1`) and, inside
  `on` only, the pushed event's payload (`event/1`). Never
  relationships or the actor: the client does not hold them.
  `AshBackendDrivenOptimisticUi.Compiler` lists the functions the client can run.
  """

  @optimistic_ui %Spark.Dsl.Section{
    name: :optimistic_ui,
    describe: "Client-side rules of this resource's actions, shipped to the client as data.",
    imports: [Ash.Expr],
    entities: [
      AshBackendDrivenOptimisticUi.Rule.__entity__(),
      AshBackendDrivenOptimisticUi.Reaction.__entity__(),
      AshBackendDrivenOptimisticUi.NotOptimistic.__entity__()
    ]
  }
  use Spark.Dsl.Extension,
    sections: [@optimistic_ui],
    transformers: [AshBackendDrivenOptimisticUi.Resource.Transformers.DeriveSets],
    verifiers: [AshBackendDrivenOptimisticUi.Resource.Verifiers.ValidateRules]
end
