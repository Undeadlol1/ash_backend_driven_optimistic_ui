defmodule Mix.Tasks.OptimisticUi.Snapshot do
  @shortdoc "Checks or rewrites the committed rule snapshots"

  @moduledoc """
  Compares every rule of `AshBackendDrivenOptimisticUi.Registry.rules/0` with the files in
  `test/optimistic_ui/__snapshots__`.

      mix optimistic_ui.snapshot            # exits non-zero listing missing, changed and stale files
      mix optimistic_ui.snapshot --update   # writes every rule, deletes files whose rule is gone

  `--dir` points at another snapshot directory.
  """

  use Mix.Task

  alias AshBackendDrivenOptimisticUi.Registry
  alias AshBackendDrivenOptimisticUi.Snapshot

  @impl true
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, switches: [update: :boolean, dir: :string])
    Mix.Task.run("app.config")

    sync(Registry.rules()["rules"], opts[:dir] || Snapshot.dir(), opts[:update] == true)
  end

  @doc "Writes (`update?`) or checks the snapshots of `rules` in `dir`; raises when a check finds drift."
  @spec sync(%{String.t() => term()}, Path.t(), boolean()) :: :ok
  def sync(rules, dir, true) do
    %{written: written, removed: removed} = Snapshot.write(rules, dir)

    Mix.shell().info("Wrote #{length(written)} snapshot(s), removed #{length(removed)} stale in #{dir}")
  end

  def sync(rules, dir, false) do
    case Snapshot.drift(rules, dir) do
      %{missing: [], changed: [], stale: []} ->
        :ok

      drift ->
        Mix.raise(
          "Rule snapshots in #{dir} are out of date. Run mix optimistic_ui.snapshot --update, review the diff, commit.\n" <>
            Enum.map_join(drift, "\n", fn {kind, keys} ->
              "  #{kind}: #{Enum.join(keys, ", ")}"
            end)
        )
    end
  end
end
