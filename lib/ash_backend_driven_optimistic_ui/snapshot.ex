defmodule AshBackendDrivenOptimisticUi.Snapshot do
  @moduledoc """
  The committed copy of every rule, one pretty-printed JSON file per
  rule at `<dir>/<type>.<action>.json`, keys sorted so a diff shows only real
  changes. `AshBackendDrivenOptimisticUi.Test` compares against it, `mix optimistic_ui.snapshot`
  rewrites it.
  """

  @default_dir "test/optimistic_ui/__snapshots__"

  @doc "The snapshot directory: the `:snapshot_dir` option, else `#{@default_dir}`."
  @spec dir(keyword()) :: Path.t()
  def dir(opts \\ []), do: Keyword.get(opts, :snapshot_dir, @default_dir)

  @doc "The file holding rule `key` (`\"<type>.<action>\"`) in `dir`."
  @spec path(Path.t(), String.t()) :: Path.t()
  def path(dir, key), do: Path.join(dir, key <> ".json")

  @doc "The file content for `rule`: key-sorted pretty JSON with a trailing newline."
  @spec render(term()) :: String.t()
  def render(rule), do: Jason.encode!(sorted(rule), pretty: true) <> "\n"

  @doc "The rule keys that have a file in `dir`, sorted."
  @spec keys_on_disk(Path.t()) :: [String.t()]
  def keys_on_disk(dir) do
    dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".json"))
    |> Enum.sort()
  end

  @doc "How `dir` differs from `rules`: rules without a file, files whose content differs, files without a rule."
  @spec drift(%{String.t() => term()}, Path.t()) :: %{
          missing: [String.t()],
          changed: [String.t()],
          stale: [String.t()]
        }
  # sobelow_skip ["Traversal.FileModule"]
  def drift(rules, dir) do
    on_disk = keys_on_disk(dir)
    {existing, missing} = rules |> Map.keys() |> Enum.sort() |> Enum.split_with(&(&1 in on_disk))

    %{
      missing: missing,
      changed: Enum.reject(existing, &(File.read!(path(dir, &1)) == render(rules[&1]))),
      stale: on_disk -- existing
    }
  end

  @doc "Writes every rule to `dir` and deletes files with no rule; returns the keys written and removed."
  @spec write(%{String.t() => term()}, Path.t()) :: %{
          written: [String.t()],
          removed: [String.t()]
        }
  # sobelow_skip ["Traversal.FileModule"]
  def write(rules, dir) do
    File.mkdir_p!(dir)
    %{stale: stale} = drift(rules, dir)

    Enum.each(stale, &File.rm!(path(dir, &1)))
    Enum.each(rules, fn {key, rule} -> File.write!(path(dir, key), render(rule)) end)

    %{written: rules |> Map.keys() |> Enum.sort(), removed: stale}
  end

  defp sorted(%{} = map) do
    map
    |> Enum.sort()
    |> Enum.map(fn {key, value} -> {key, sorted(value)} end)
    |> Jason.OrderedObject.new()
  end

  defp sorted(list) when is_list(list), do: Enum.map(list, &sorted/1)
  defp sorted(other), do: other
end
