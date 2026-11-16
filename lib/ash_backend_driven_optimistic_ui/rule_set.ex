defmodule AshBackendDrivenOptimisticUi.RuleSet do
  @moduledoc """
  A ready Ash resource that serves the rules.

  Add it to a domain and expose its `:rules` action with your API layer, like
  any other action:

      resources do
        resource AshBackendDrivenOptimisticUi.RuleSet
      end

  The action returns `AshBackendDrivenOptimisticUi.Registry.rules/0`. The
  resource holds no data and is never counted as a rule resource.
  """

  use Ash.Resource, domain: nil

  actions do
    action :rules, :map do
      run fn _input, _context ->
        {:ok, AshBackendDrivenOptimisticUi.Registry.rules()}
      end
    end
  end
end
