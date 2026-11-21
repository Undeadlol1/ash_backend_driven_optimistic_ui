defmodule AshBackendDrivenOptimisticUi.Rules do
  @moduledoc """
  A resource's rules as JSON-ready data for the client.

  Rules are keyed `"<type>.<action>"`, where `<type>` is the resource's
  JSON:API type or, without one, its module's last segment underscored. Each
  rule is `%{"effects" => [effect]}`, effects in order:

    * `%{"set" => %{"attr" => json_logic}, "source" => "derived" | "declared"}`
    * `%{"push" => %{"event" => "xp_awarded", "payload" => %{"key" => json_logic}}}`; the
      payload also gets `"id"`, `{"var": "ctx.push_ids.<event>.<label>"}` (see
      `AshBackendDrivenOptimisticUi.PushId`), except in the rule of a create action
    * `%{"where" => json_logic, "effects" => [effect]}`
    * `%{"insert" => %{"at" => "start" | "end" | %{"sorted_by" => "field"}}}`: put the record
      the sets build into the list, at an end or before the first row whose `field` sorts after its own
    * `%{"remove" => %{}}`: take the record out of the list
    * `%{"clear" => %{"from" => path}}`: empty the nested lists at `path`
    * `%{"edit" => %{"from" => path}}`: apply the sets to the record's own row in the nested lists at `path`

  An insert with `"into"`, or a remove with `"from"`, works on a list nested
  inside the one record the client holds. The path is a list of steps,
  `%{"key" => "exercises"}` or `%{"key" => "exercises", "match" => %{"field" => json_logic}}`,
  the latter keeping only the rows whose `field` equals the value.

  An expression `AshBackendDrivenOptimisticUi.Compiler` cannot compile raises, so a rule
  set is never half-built.
  """

  alias AshBackendDrivenOptimisticUi.Compiler
  alias AshBackendDrivenOptimisticUi.Effect.Clear
  alias AshBackendDrivenOptimisticUi.Effect.Insert
  alias AshBackendDrivenOptimisticUi.Effect.Push
  alias AshBackendDrivenOptimisticUi.Effect.Remove
  alias AshBackendDrivenOptimisticUi.Effect.Set
  alias AshBackendDrivenOptimisticUi.Effect.Where
  alias AshBackendDrivenOptimisticUi.Info
  alias AshBackendDrivenOptimisticUi.PushId

  @doc "Every `optimistic` of `resource`, keyed `\"<type>.<action>\"`."
  @spec for_resource(Ash.Resource.t()) :: %{String.t() => map()}
  def for_resource(resource) do
    type = type(resource)

    Map.new(Info.rules(resource), fn rule ->
      label = if PushId.identified?(resource, rule.action), do: rule.action

      {"#{type}.#{rule.action}", %{"effects" => compile_effects(rule.effects, resource, rule.action, label)}}
    end)
  end

  @doc "Every `on` of `resource`, keyed by event name."
  @spec reactions_for_resource(Ash.Resource.t()) :: %{String.t() => [map()]}
  def reactions_for_resource(resource) do
    Map.new(Info.reactions(resource), fn reaction ->
      {Atom.to_string(reaction.event), compile_effects(reaction.effects, resource, reaction.event, reaction.event)}
    end)
  end

  @doc "The JSON:API type of `resource`, or its module's last segment underscored."
  @spec type(Ash.Resource.t()) :: String.t()
  def type(resource) do
    json_api_type(resource) ||
      resource |> Module.split() |> List.last() |> Macro.underscore()
  end

  defp json_api_type(resource) do
    if Code.ensure_loaded?(AshJsonApi.Resource.Info),
      do: AshJsonApi.Resource.Info.type(resource)
  end

  defp compile_effects(effects, resource, trigger, label),
    do: Enum.map(effects, &compile_effect(&1, resource, trigger, label))

  defp compile_effect(%Set{attribute: attribute, value: value, derived?: derived?, from: from}, resource, trigger, _label) do
    %{
      "set" => %{Atom.to_string(attribute) => compile!(value, resource, trigger, from)},
      "source" => if(derived?, do: "derived", else: "declared")
    }
  end

  defp compile_effect(%Push{event: event, payload: payload}, resource, trigger, label) do
    %{
      "push" => %{
        "event" => Atom.to_string(event),
        "payload" => with_id(compile_fields(payload, resource, trigger), event, label)
      }
    }
  end

  defp compile_effect(%Where{condition: condition, effects: effects}, resource, trigger, label) do
    %{
      "where" => compile!(condition, resource, trigger),
      "effects" => compile_effects(effects, resource, trigger, label)
    }
  end

  defp compile_effect(%Insert{at: position, into: path}, resource, trigger, _label),
    do: %{"insert" => with_path(%{"at" => position(position)}, "into", path, resource, trigger)}

  defp compile_effect(%Remove{from: path}, resource, trigger, _label),
    do: %{"remove" => with_path(%{}, "from", path, resource, trigger)}

  defp compile_effect(%Clear{from: path}, resource, trigger, _label),
    do: %{"clear" => with_path(%{}, "from", path, resource, trigger)}

  defp compile_effect(%AshBackendDrivenOptimisticUi.Effect.Edit{from: path}, resource, trigger, _label),
    do: %{"edit" => with_path(%{}, "from", path, resource, trigger)}

  defp position({:sorted_by, field}), do: %{"sorted_by" => Atom.to_string(field)}
  defp position(end_of_list), do: Atom.to_string(end_of_list)

  defp with_path(options, _name, nil, _resource, _trigger), do: options

  defp with_path(options, name, path, resource, trigger),
    do: Map.put(options, name, Enum.map(path, &compile_step(&1, resource, trigger)))

  defp compile_step({key, match}, resource, trigger),
    do: %{"key" => Atom.to_string(key), "match" => compile_fields(match, resource, trigger)}

  defp compile_step(key, _resource, _trigger), do: %{"key" => Atom.to_string(key)}

  defp compile_fields(fields, resource, trigger),
    do: Map.new(fields, fn {key, value} -> {Atom.to_string(key), compile!(value, resource, trigger)} end)

  defp with_id(payload, _event, nil), do: payload

  defp with_id(payload, event, label), do: Map.put(payload, "id", %{"var" => PushId.variable(event, label)})

  defp compile!(expression, resource, trigger, from \\ nil) do
    case Compiler.compile(expression, resource: resource, action: trigger) do
      {:ok, compiled} ->
        compiled

      {:error, {:unsupported, node}} ->
        raise ArgumentError,
              "#{inspect(resource)} rule #{inspect(trigger)}#{from_note(from)} uses #{inspect(node)}, " <>
                "which the client cannot evaluate (see AshBackendDrivenOptimisticUi.Compiler)"
    end
  end

  defp from_note(nil), do: ""
  defp from_note(module), do: " (from #{inspect(module)}.optimistic_sets/1)"
end
