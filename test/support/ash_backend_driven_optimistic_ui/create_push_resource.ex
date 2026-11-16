defmodule AshBackendDrivenOptimisticUi.TestSupport.CreatePushResource do
  @moduledoc "A resource whose create rule pushes an event, which has no record before the write."

  use Ash.Resource,
    domain: AshBackendDrivenOptimisticUi.TestSupport.SampleDomain,
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  optimistic_ui do
    optimistic :create do
      push :created, balance: expr(arg(:balance))
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:balance]
    end
  end

  attributes do
    uuid_primary_key :id
    update_timestamp :updated_at, public?: true
    attribute :balance, :integer, public?: true
  end
end
