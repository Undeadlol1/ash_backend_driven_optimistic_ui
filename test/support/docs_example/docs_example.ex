defmodule AshBackendDrivenOptimisticUi.TestSupport.Docs.Domain do
  @moduledoc "The todo app from the README and the How it works guide."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshBackendDrivenOptimisticUi.TestSupport.Docs.Todo
    resource AshBackendDrivenOptimisticUi.TestSupport.Docs.UserLevel
  end
end

defmodule AshBackendDrivenOptimisticUi.TestSupport.Docs.OptimisticCtx do
  @moduledoc false
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:updated_at]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &%{push_ids: AshBackendDrivenOptimisticUi.PushId.for_record(&1)})
  end
end

defmodule AshBackendDrivenOptimisticUi.TestSupport.Docs.Todo do
  @moduledoc false

  use Ash.Resource,
    domain: AshBackendDrivenOptimisticUi.TestSupport.Docs.Domain,
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  optimistic_ui do
    optimistic :create do
      insert at: :end
    end

    optimistic :complete do
      where expr(not done) do
        set :done, true
        push :xp_awarded, amount: 10
      end
    end
  end

  actions do
    defaults [:read]
    create :create, accept: [:title]
    update :complete
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :done, :boolean, public?: true, default: false
    update_timestamp :updated_at
  end

  calculations do
    calculate :ctx, :map, AshBackendDrivenOptimisticUi.TestSupport.Docs.OptimisticCtx, public?: true
  end
end

defmodule AshBackendDrivenOptimisticUi.TestSupport.Docs.UserLevel do
  @moduledoc false

  use Ash.Resource,
    domain: AshBackendDrivenOptimisticUi.TestSupport.Docs.Domain,
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  optimistic_ui do
    on :xp_awarded do
      set :total_xp, expr(total_xp + event(:amount))
    end
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :total_xp, :integer, public?: true, default: 0
  end
end
