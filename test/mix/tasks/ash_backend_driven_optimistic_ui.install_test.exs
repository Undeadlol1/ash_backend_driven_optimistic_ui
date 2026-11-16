defmodule Mix.Tasks.AshBackendDrivenOptimisticUi.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  defp install(project), do: Igniter.compose_task(project, "ash_backend_driven_optimistic_ui.install", [])

  defp source(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  describe "GIVEN a fresh project" do
    setup do
      %{igniter: install(test_project())}
    end

    test "WHEN the installer runs THEN config.exs names the app and its PubSub", %{
      igniter: igniter
    } do
      assert source(igniter, "config/config.exs") =~
               "config :ash_backend_driven_optimistic_ui, otp_app: :test, pubsub: Test.PubSub"
    end

    test "WHEN the installer runs THEN .formatter.exs imports the library", %{igniter: igniter} do
      assert_has_patch(igniter, ".formatter.exs", """
      + |  import_deps: [:ash_backend_driven_optimistic_ui]
      """)
    end

    test "WHEN the installer runs THEN one notice names what the app must send to the client", %{
      igniter: igniter
    } do
      assert [notice] = igniter.notices

      assert notice =~ "resource AshBackendDrivenOptimisticUi.RuleSet"
      assert notice =~ "AshBackendDrivenOptimisticUi.PushCollector.open()"
      assert notice =~ "AshBackendDrivenOptimisticUi.PushCollector.drain_reconciliation(ids)"
      assert notice =~ "AshBackendDrivenOptimisticUi.PushCollector.record/2"
    end

    test "WHEN the installer runs a second time THEN nothing changes" do
      once = test_project() |> install() |> apply_igniter!()

      once |> install() |> assert_unchanged(["config/config.exs", ".formatter.exs"])
    end
  end
end
