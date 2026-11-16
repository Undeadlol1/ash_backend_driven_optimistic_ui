defmodule AshBackendDrivenOptimisticUi.RegistryConfigTest do
  use ExUnit.Case, async: false

  alias AshBackendDrivenOptimisticUi.Registry
  alias AshBackendDrivenOptimisticUi.TestSupport.CycleDomain

  @host_app :optimistic_ui_host_app

  setup do
    previous_otp_app = Application.fetch_env!(:ash_backend_driven_optimistic_ui, :otp_app)
    Application.put_env(:ash_backend_driven_optimistic_ui, :otp_app, @host_app)
    Application.put_env(@host_app, :ash_domains, [CycleDomain])
    :persistent_term.erase({Registry, :rules})

    on_exit(fn ->
      Application.put_env(:ash_backend_driven_optimistic_ui, :otp_app, previous_otp_app)
      Application.delete_env(@host_app, :ash_domains)
      :persistent_term.erase({Registry, :rules})
    end)
  end

  describe "GIVEN a host app configured through :otp_app" do
    test "WHEN rules/0 is read THEN it builds from that app's :ash_domains" do
      assert Registry.rules() == Registry.rules([CycleDomain])
    end
  end
end
