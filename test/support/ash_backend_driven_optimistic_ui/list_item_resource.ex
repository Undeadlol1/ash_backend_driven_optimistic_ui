defmodule AshBackendDrivenOptimisticUi.TestSupport.ListItemResource do
  @moduledoc """
  A row of a list the client holds: a create inserts it (at an end or in title
  order), a destroy removes it, either in a list of its own or in the `items`
  of a group inside the one record the client holds, which a generic action can
  empty and an update can edit in place.
  """

  use Ash.Resource,
    domain: AshBackendDrivenOptimisticUi.TestSupport.SampleDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  ets do
    private? true
  end

  optimistic_ui do
    optimistic :add do
      insert at: :start
    end

    optimistic :discard do
      remove()
    end

    optimistic :rename do
      set :title, expr(arg(:title))
    end

    optimistic :add_to_group do
      insert at: :end, into: [{:groups, id: expr(arg(:group_id))}, :items]
    end

    optimistic :discard_from_group do
      remove from: [:groups, :items]
    end

    optimistic :add_sorted do
      insert at: {:sorted_by, :title}
    end

    optimistic :discard_all do
      clear from: [:groups, :items]
    end

    optimistic :retitle_in_group do
      edit from: [:groups, :items]

      where expr(has_arg(:title)) do
        set :title, expr(arg(:title))
      end
    end

    on :retitled do
      where expr(is_nil(title)) do
        where expr(event(:title) != "") do
          set(:title, expr(event(:title)))
        end
      end
    end
  end

  actions do
    defaults [:read]

    create :add do
      accept [:title]
    end

    update :rename do
      accept [:title]
    end

    destroy :discard

    create :add_to_group do
      accept [:title, :group_id]
    end

    destroy :discard_from_group

    create :add_sorted do
      accept [:title]
    end

    action :discard_all, :boolean do
      run fn _input, _context -> {:ok, true} end
    end

    update :retitle_in_group do
      accept [:title]
    end
  end

  attributes do
    uuid_primary_key :id
    update_timestamp :updated_at, public?: true
    attribute :title, :string, public?: true, constraints: [max_length: 255]
    attribute :group_id, :uuid, public?: true
  end
end
