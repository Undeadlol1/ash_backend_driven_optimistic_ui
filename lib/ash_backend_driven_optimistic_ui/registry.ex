defmodule AshBackendDrivenOptimisticUi.Registry do
  @moduledoc """
  Every rule of the host app in one payload, with a version.

  `rules/0` reads the `:ash_domains` of the app named by
  `config :ash_backend_driven_optimistic_ui, otp_app: :my_app` and caches the result in `:persistent_term`; `rules/1` builds from an explicit domain list,
  uncached. The payload is `%{"version" => hash, "rules" => rules}` where
  `hash` is the first 16 hex characters of the SHA-256 of the rules.

  Each rule is `AshBackendDrivenOptimisticUi.Rules`' `%{"effects" => [...]}` plus
  `"reactions"`: every `on` of any resource that answers an event the rule
  pushes, following pushes made by reactions in turn, in discovery order:

      %{"on" => "xp_awarded", "type" => "wallet", "effects" => [effect]}

  A reaction runs once per `{event, type}` per rule, so cycles end.
  """

  alias Ash.Domain.Info, as: DomainInfo
  alias AshBackendDrivenOptimisticUi.Resource
  alias AshBackendDrivenOptimisticUi.Rules

  @cache_key {__MODULE__, :rules}

  @doc "The `:ash_domains` of the host app named by the `:otp_app` setting."
  @spec app_domains() :: [module()]
  def app_domains do
    :ash_backend_driven_optimistic_ui
    |> Application.get_env(:otp_app)
    |> Application.get_env(:ash_domains, [])
  end

  @doc "The payload for the app's registered domains, built once per VM."
  @spec rules() :: %{String.t() => term()}
  def rules do
    case :persistent_term.get(@cache_key, nil) do
      nil ->
        built = rules(app_domains())
        :persistent_term.put(@cache_key, built)
        built

      cached ->
        cached
    end
  end

  @doc "The payload for `domains`, uncached."
  @spec rules([module()]) :: %{String.t() => term()}
  def rules(domains) do
    resources = rule_resources(domains)
    reactions = Enum.flat_map(resources, &resource_reactions/1)

    merged =
      resources
      |> Enum.map(&Rules.for_resource/1)
      |> Enum.reduce(%{}, &Map.merge(&2, &1))
      |> Map.new(fn {key, rule} ->
        {key, Map.put(rule, "reactions", chain(rule["effects"], reactions))}
      end)

    %{"version" => version_of(merged), "rules" => merged}
  end

  @doc "Just the hash of `rules/0`."
  @spec version() :: String.t()
  def version, do: rules()["version"]

  @doc "Every resource of `domains` that declares rules or reactions."
  @spec rule_resources([module()]) :: [module()]
  def rule_resources(domains) do
    for domain <- domains,
        resource <- DomainInfo.resources(domain),
        Resource in Spark.extensions(resource),
        do: resource
  end

  defp resource_reactions(resource) do
    type = Rules.type(resource)

    for {event, effects} <- Rules.reactions_for_resource(resource),
        do: %{"on" => event, "type" => type, "effects" => effects}
  end

  defp chain(effects, reactions), do: walk(pushes(effects), reactions, MapSet.new(), [])

  defp walk([], _reactions, _visited, found), do: Enum.reverse(found)

  defp walk([event | queue], reactions, visited, found) do
    fresh =
      Enum.reject(reactions, &(&1["on"] != event or MapSet.member?(visited, {event, &1["type"]})))

    visited = Enum.reduce(fresh, visited, &MapSet.put(&2, {event, &1["type"]}))
    next = Enum.flat_map(fresh, &pushes(&1["effects"]))

    walk(queue ++ next, reactions, visited, Enum.reverse(fresh, found))
  end

  defp pushes(effects) do
    Enum.flat_map(effects, fn
      %{"push" => %{"event" => event}} -> [event]
      %{"effects" => nested} -> pushes(nested)
      _set -> []
    end)
  end

  defp version_of(rules) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(rules, [:deterministic]))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end
