defmodule AshBackendDrivenOptimisticUi.TestSupport.SampleResource do
  @moduledoc """
  A resource whose actions mix readable changes, an opaque change and a
  `optimistic_ui` block, so derivation, overrides and compilation are exercised
  against real Ash action definitions.
  """

  use Ash.Resource,
    domain: AshBackendDrivenOptimisticUi.TestSupport.SampleDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  ets do
    private? true
  end

  optimistic_ui do
    optimistic :award_xp do
      push :xp_awarded, xp_amount: expr(arg(:xp_amount))

      where expr(arg(:xp_amount) >= xp_to_next_level) do
        set :current_level, expr(current_level + 1)
        push :level_up, message: expr(^context(:level_up_message))
      end
    end

    optimistic :spend do
      set :balance, expr(balance - arg(:cost))
    end

    optimistic :refund do
      set :spendable, expr(balance + arg(:amount) - 1)
    end

    not_optimistic :create, because: :admin

    on :level_up do
      set :balance, expr(balance + 1)
    end

    optimistic :open do
      set :current_level, 1
    end

    optimistic :tip do
      push :tipped, amount: expr(arg(:amount))
    end

    optimistic :close do
      push :closed, balance: expr(balance)
    end

    on :tipped do
      set :balance, expr(balance + event(:amount))
      push :tip_received, amount: expr(event(:amount))
    end
  end

  actions do
    defaults [:read]

    destroy :close

    create :create do
      accept [:total_xp, :current_level, :xp_to_next_level, :balance, :ctx, :owner_id]
    end

    create :open do
      accept [:balance, :current_level]

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :current_level, 1)
      end
    end

    update :refund do
      require_atomic? false
      argument :amount, :integer, allow_nil?: false
      change atomic_update(:balance, expr(balance + ^arg(:amount)))
    end

    update :tip do
      require_atomic? false
      argument :amount, :integer, allow_nil?: false
      argument :jar_id, :uuid, allow_nil?: false
      change atomic_update(:balance, expr(balance - ^arg(:amount)))

      change after_action(fn changeset, record, _context ->
               jar =
                 Ash.get!(__MODULE__, Ash.Changeset.get_argument(changeset, :jar_id), authorize?: false)

               amount = Ash.Changeset.get_argument(changeset, :amount)

               jar
               |> Ash.Changeset.for_update(:refund, %{amount: amount})
               |> Ash.update!(authorize?: false)

               {:ok, record}
             end)
    end

    update :award_xp do
      require_atomic? false
      argument :xp_amount, :decimal, allow_nil?: false
      change atomic_update(:total_xp, expr(total_xp + ^arg(:xp_amount)))
    end

    update :spend do
      require_atomic? false
      argument :cost, :integer, allow_nil?: false
      change set_attribute(:current_level, 1)
      change set_attribute(:balance, arg(:cost))
      change set_attribute(:total_xp, 0), where: [argument_equals(:cost, 0)]
      change fn changeset, _context -> changeset end
    end
  end

  policies do
    policy action_type([:create, :update, :destroy]) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(is_nil(owner_id))
      authorize_if expr(owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id
    update_timestamp :updated_at, public?: true
    attribute :ctx, :map, public?: true
    attribute :total_xp, :decimal, public?: true
    attribute :current_level, :integer, public?: true
    attribute :xp_to_next_level, :decimal, public?: true
    attribute :balance, :integer, public?: true
    attribute :owner_id, :uuid, public?: true
  end

  calculations do
    calculate :spendable, :integer, expr(balance - 1), public?: true
  end
end
