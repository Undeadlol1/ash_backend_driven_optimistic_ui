if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshBackendDrivenOptimisticUi.Install do
    @shortdoc "Installs AshBackendDrivenOptimisticUi: config and formatter."

    @moduledoc """
    #{@shortdoc}

    ## Example

    ```bash
    mix igniter.install ash_backend_driven_optimistic_ui
    ```

    Does the setup from the README, and is safe to run again:

    * sets `otp_app` and `pubsub` in `config/config.exs`
    * adds the library to `import_deps` in `.formatter.exs`

    A notice then names the two things your app must send to the client.
    """

    use Igniter.Mix.Task

    alias Igniter.Project.Config

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        group: :ash,
        example: "mix igniter.install ash_backend_driven_optimistic_ui"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app = Igniter.Project.Application.app_name(igniter)
      pubsub = Igniter.Project.Module.module_name(igniter, "PubSub")

      igniter
      |> Config.configure(
        "config.exs",
        :ash_backend_driven_optimistic_ui,
        [:otp_app],
        app
      )
      |> Config.configure(
        "config.exs",
        :ash_backend_driven_optimistic_ui,
        [:pubsub],
        pubsub
      )
      |> Igniter.Project.Formatter.import_dep(:ash_backend_driven_optimistic_ui)
      |> Igniter.add_notice("""
      Two things are left for you. Send both to the client, over any transport.

      1. Send the rules: add `resource AshBackendDrivenOptimisticUi.RuleSet` to a domain
         and expose its :rules action with your API layer.

      2. Around each save, call AshBackendDrivenOptimisticUi.PushCollector.open()
         before the action. Send AshBackendDrivenOptimisticUi.PushCollector.drain_reconciliation(ids)
         with the answer.

      Whatever sends pushes must call AshBackendDrivenOptimisticUi.PushCollector.record/2.
      Docs: https://hexdocs.pm/ash_backend_driven_optimistic_ui
      """)
    end
  end
else
  defmodule Mix.Tasks.AshBackendDrivenOptimisticUi.Install do
    @shortdoc "Installs AshBackendDrivenOptimisticUi. Needs igniter."

    @moduledoc @shortdoc

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_backend_driven_optimistic_ui.install' requires igniter to be run.

      Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
