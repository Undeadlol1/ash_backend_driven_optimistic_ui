defmodule AshBackendDrivenOptimisticUi.TestSupport.CycleResource do
  @moduledoc """
  Reacts to `:xp_awarded` by pushing `:level_up` and to `:level_up` by pushing
  `:xp_awarded`, so a rule that starts either event loops through it.
  """

  use Ash.Resource,
    domain: AshBackendDrivenOptimisticUi.TestSupport.CycleDomain,
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  optimistic_ui do
    on :xp_awarded do
      push :level_up, message: expr(balance)
    end

    on :level_up do
      push :xp_awarded, xp_amount: expr(balance)
    end
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :balance, :integer, public?: true
  end
end
