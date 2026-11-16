defmodule AshBackendDrivenOptimisticUi.TestSupport.UpdateFieldsResource do
  @moduledoc """
  Updates that accept attributes, so an update's derived effects are exercised:
  each accepted field is applied only when the input carries it.
  """

  use Ash.Resource,
    domain: AshBackendDrivenOptimisticUi.TestSupport.UpdateFieldsDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  ets do
    private? true
  end

  optimistic_ui do
    optimistic :edit
    optimistic :edit_nothing
    optimistic :edit_through_argument
    optimistic :edit_counting
    optimistic :remove_titled
    optimistic :make

    optimistic :edit_declared_title do
      set :title, expr(arg(:title))
    end

    optimistic :edit_declared_in_where do
      where expr(has_arg(:title)) do
        set :title, expr(arg(:title))
      end
    end

    optimistic :edit_disagreeing do
      set :count, expr(arg(:count) + 1)
    end
  end

  actions do
    defaults [:read]

    create :make do
      accept [:title]
    end

    update :edit do
      accept [:title, :note]
    end

    update :edit_nothing do
      accept []
      argument :label, :string
    end

    update :edit_through_argument do
      accept [:title]
      argument :label, :string
      change set_attribute(:title, arg(:label))
    end

    update :edit_counting do
      require_atomic? false
      accept [:count, :title]
      change atomic_update(:count, expr(count + 1))
    end

    update :edit_declared_title do
      accept [:title, :note]
    end

    update :edit_declared_in_where do
      accept [:title, :note]
    end

    update :edit_disagreeing do
      accept [:count, :note]
    end

    destroy :remove_titled do
      require_atomic? false
      accept [:title]
    end
  end

  attributes do
    uuid_primary_key :id
    update_timestamp :updated_at, public?: true
    attribute :title, :string, public?: true
    attribute :note, :string, public?: true
    attribute :count, :integer, public?: true
  end
end
