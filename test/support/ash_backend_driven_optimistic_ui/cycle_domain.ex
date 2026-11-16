defmodule AshBackendDrivenOptimisticUi.TestSupport.CycleDomain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
    resource AshBackendDrivenOptimisticUi.TestSupport.SampleResource
    resource AshBackendDrivenOptimisticUi.TestSupport.CycleResource
  end
end
