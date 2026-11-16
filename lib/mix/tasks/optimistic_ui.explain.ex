defmodule Mix.Tasks.OptimisticUi.Explain do
  @shortdoc "Prints a rule with each set marked derived or declared"

  @moduledoc """
  Prints the compiled rule of one action, then the reactions that follow its
  pushes.

      mix optimistic_ui.explain wallet.award_xp
  """

  use Mix.Task

  alias AshBackendDrivenOptimisticUi.Registry

  @impl true
  def run([key]) do
    Mix.Task.run("app.config")

    case Registry.rules()["rules"][key] do
      nil ->
        Mix.raise("No rule #{key}. Known: #{Enum.join(Map.keys(Registry.rules()["rules"]), ", ")}")

      rule ->
        key |> render(rule) |> Mix.shell().info()
    end
  end

  def run(_args), do: Mix.raise("Usage: mix optimistic_ui.explain <type>.<action>")

  @doc "The printable text for `rule`."
  @spec render(String.t(), map()) :: String.t()
  def render(key, %{"effects" => effects, "reactions" => reactions}) do
    Enum.join(
      [key | lines(effects, 1)] ++
        Enum.flat_map(reactions, &["on #{&1["on"]} (#{&1["type"]})" | lines(&1["effects"], 1)]),
      "\n"
    )
  end

  defp lines(effects, depth), do: Enum.flat_map(effects, &effect_lines(&1, depth))

  defp effect_lines(%{"set" => sets, "source" => source}, depth) do
    for {attribute, rule} <- sets,
        do: indent("set #{attribute} = #{json(rule)}  [#{source}]", depth)
  end

  defp effect_lines(%{"push" => %{"event" => event, "payload" => payload}}, depth),
    do: [indent("push #{event} #{json(payload)}", depth)]

  defp effect_lines(%{"where" => condition, "effects" => nested}, depth),
    do: [indent("where #{json(condition)}", depth) | lines(nested, depth + 1)]

  defp effect_lines(%{"insert" => %{"at" => %{"sorted_by" => field}} = options}, depth),
    do: [indent("insert sorted by #{field}" <> path(" into ", options["into"]), depth)]

  defp effect_lines(%{"insert" => %{"at" => position} = options}, depth),
    do: [indent("insert at #{position}" <> path(" into ", options["into"]), depth)]

  defp effect_lines(%{"clear" => options}, depth), do: [indent("clear" <> path(" from ", options["from"]), depth)]

  defp effect_lines(%{"edit" => options}, depth), do: [indent("edit" <> path(" from ", options["from"]), depth)]

  defp effect_lines(%{"remove" => options}, depth), do: [indent("remove" <> path(" from ", options["from"]), depth)]

  defp path(_prefix, nil), do: ""
  defp path(prefix, steps), do: prefix <> Enum.map_join(steps, ".", &step/1)

  defp step(%{"key" => key, "match" => match}),
    do: "#{key}[#{Enum.map_join(match, ", ", fn {field, value} -> "#{field} = #{json(value)}" end)}]"

  defp step(%{"key" => key}), do: key

  defp indent(text, depth), do: String.duplicate("  ", depth) <> text
  defp json(rule), do: Jason.encode!(rule)
end
