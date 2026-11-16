defmodule AshBackendDrivenOptimisticUi.TestSupport.UpdateFieldsDomain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
    resource AshBackendDrivenOptimisticUi.TestSupport.UpdateFieldsResource
    resource AshBackendDrivenOptimisticUi.TestSupport.ChangeModuleResource
  end
end
