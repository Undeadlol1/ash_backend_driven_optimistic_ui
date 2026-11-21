defmodule AshBackendDrivenOptimisticUi.TestSupport.NameType do
  @moduledoc false
  use Ash.Type.NewType, subtype_of: :string
end

defmodule AshBackendDrivenOptimisticUi.TestSupport.ComparisonResource do
  @moduledoc """
  Updates that compare texts, dates, numbers and nil values, so the compiled
  rule can be checked against what the real action does.
  """

  use Ash.Resource,
    domain: AshBackendDrivenOptimisticUi.TestSupport.UpdateFieldsDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  ets do
    private? true
  end

  optimistic_ui do
    optimistic :text_before_m
    optimistic :born_before_2000
    optimistic :born_before_cutoff
    optimistic :amount_over_five
    optimistic :score_over_five
    optimistic :score_differs_from_five
    optimistic :score_equals_limit
    optimistic :score_in_list
    optimistic :name_over_five
    optimistic :shout_before_whisper
    optimistic :at_from_2020
    optimistic :at_sec_from_2020
    optimistic :at_since
    optimistic :at_before_now
  end

  actions do
    defaults [:read, create: [:name, :born_on, :amount, :score, :limit, :at, :at_sec]]

    update :text_before_m do
      require_atomic? false
      change atomic_update(:verdict, expr(if(name < "m", do: "yes", else: "no")))
    end

    update :born_before_2000 do
      require_atomic? false
      change atomic_update(:verdict, expr(if(born_on < ^~D[2000-01-01], do: "yes", else: "no")))
    end

    update :born_before_cutoff do
      require_atomic? false
      argument :cutoff, :date, allow_nil?: false
      change atomic_update(:verdict, expr(if(born_on < ^arg(:cutoff), do: "yes", else: "no")))
    end

    update :amount_over_five do
      require_atomic? false
      change atomic_update(:verdict, expr(if(amount > 5, do: "yes", else: "no")))
    end

    update :score_over_five do
      require_atomic? false
      change atomic_update(:verdict, expr(if(score > 5, do: "yes", else: "no")))
    end

    update :score_differs_from_five do
      require_atomic? false
      change atomic_update(:verdict, expr(if(score != 5, do: "yes", else: "no")))
    end

    update :score_equals_limit do
      require_atomic? false
      change atomic_update(:verdict, expr(if(score == limit, do: "yes", else: "no")))
    end

    update :score_in_list do
      require_atomic? false
      change atomic_update(:verdict, expr(if(score in [1, 2], do: "yes", else: "no")))
    end

    update :name_over_five do
      require_atomic? false
      change atomic_update(:verdict, expr(if(name > 5, do: "yes", else: "no")))
    end

    update :shout_before_whisper do
      require_atomic? false
      change atomic_update(:verdict, expr(if(shout < whisper, do: "yes", else: "no")))
    end

    update :at_from_2020 do
      require_atomic? false
      change atomic_update(:verdict, expr(if(at >= ^~U[2020-01-01 00:00:00Z], do: "yes", else: "no")))
    end

    update :at_sec_from_2020 do
      require_atomic? false
      change atomic_update(:verdict, expr(if(at_sec >= ^~U[2020-01-01 00:00:00Z], do: "yes", else: "no")))
    end

    update :at_since do
      require_atomic? false
      argument :since, :utc_datetime_usec, allow_nil?: false
      change atomic_update(:verdict, expr(if(at >= ^arg(:since), do: "yes", else: "no")))
    end

    update :at_before_now do
      require_atomic? false
      change atomic_update(:verdict, expr(if(at < now(), do: "yes", else: "no")))
    end
  end

  relationships do
    has_many :children, __MODULE__, destination_attribute: :parent_id
  end

  calculations do
    calculate :shout, :string, expr(name <> "!"), public?: true
    calculate :whisper, :string, expr(name <> "?"), public?: true
  end

  aggregates do
    first :first_child_name, :children, :name, public?: true
  end

  attributes do
    attribute :parent_id, :uuid
    attribute :nickname, AshBackendDrivenOptimisticUi.TestSupport.NameType, public?: true
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :born_on, :date, public?: true
    attribute :amount, :decimal, public?: true
    attribute :score, :integer, public?: true
    attribute :limit, :integer, public?: true
    attribute :at, :utc_datetime_usec, public?: true
    attribute :at_sec, :utc_datetime, public?: true
    attribute :verdict, :string, public?: true
  end
end
