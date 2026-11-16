defmodule AshBackendDrivenOptimisticUi.TestSupport.UncompilableResource do
  @moduledoc "A resource whose rule uses a function the client cannot evaluate."

  use Ash.Resource,
    domain: AshBackendDrivenOptimisticUi.TestSupport.SampleDomain,
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  optimistic_ui do
    optimistic :touch do
      set :balance, expr(today())
    end
  end

  actions do
    defaults [:read]
    update :touch
  end

  attributes do
    uuid_primary_key :id
    attribute :balance, :integer, public?: true
  end
end
