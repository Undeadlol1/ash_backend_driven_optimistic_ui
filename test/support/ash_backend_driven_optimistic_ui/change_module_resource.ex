defmodule AshBackendDrivenOptimisticUi.TestSupport.ChangeModuleResource do
  @moduledoc """
  Actions that use change modules, so a change that describes its own effect
  for the client is exercised.
  """

  use Ash.Resource,
    domain: AshBackendDrivenOptimisticUi.TestSupport.UpdateFieldsDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  alias AshBackendDrivenOptimisticUi.TestSupport.Bump
  alias AshBackendDrivenOptimisticUi.TestSupport.Label
  alias AshBackendDrivenOptimisticUi.TestSupport.Liar
  alias AshBackendDrivenOptimisticUi.TestSupport.Silent

  ets do
    private? true
  end

  optimistic_ui do
    optimistic :bump
    optimistic :bump_by_five
    optimistic :silent
    optimistic :guarded
    optimistic :label
    optimistic :liar
    optimistic :bump_accepting
    optimistic :make_bumped

    optimistic :bump_declared do
      set :count, expr(count + 100)
    end
  end

  actions do
    defaults [:read]

    create :make do
      accept [:count]
    end

    create :make_bumped do
      accept [:count]
      change {Bump, by: 1}
    end

    update :bump do
      require_atomic? false
      change {Bump, by: 2}
    end

    update :bump_by_five do
      require_atomic? false
      change {Bump, by: 5}
    end

    update :silent do
      require_atomic? false
      change Silent
    end

    update :guarded do
      require_atomic? false
      accept [:note]
      change {Bump, by: 2}, where: present(:note)
    end

    update :label do
      require_atomic? false
      change Label
    end

    update :liar do
      require_atomic? false
      change Liar
    end

    update :bump_accepting do
      require_atomic? false
      accept [:count]
      change {Bump, by: 1}
    end

    update :bump_declared do
      require_atomic? false
      change {Bump, by: 2}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :note, :string, public?: true
    attribute :count, :integer, public?: true, default: 0, allow_nil?: false
  end
end
