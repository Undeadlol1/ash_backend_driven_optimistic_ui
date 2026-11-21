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
  end

  actions do
    defaults [:read, create: [:name, :born_on, :amount, :score, :limit]]

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
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :born_on, :date, public?: true
    attribute :amount, :decimal, public?: true
    attribute :score, :integer, public?: true
    attribute :limit, :integer, public?: true
    attribute :verdict, :string, public?: true
  end
end
