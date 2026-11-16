defmodule AshBackendDrivenOptimisticUi.PushId do
  @moduledoc """
  The id of an optimistic push, computed from the record as it was before the
  write: `<type>:<record id>:<updated_at>:<event>:<label>`.

  `label` is the `optimistic` action name for a push made inside `optimistic`, and
  the answered event's name for a push made inside `on`. The record's
  `updated_at` moves on every write, so the next write's ids are new by
  themselves and nothing has to be remembered.

  The server computes the id with `for/3` both when the client shows the push at once
  (through the record's `ctx.push_ids`, see `for_record/1`) and when the
  notifier really sends it, so the two match by construction.

  An `optimistic` rule of a create or generic action has no record before the
  write, so its pushes get no id.
  """

  alias AshBackendDrivenOptimisticUi.Effect.Push
  alias AshBackendDrivenOptimisticUi.Effect.Where
  alias AshBackendDrivenOptimisticUi.Info
  alias AshBackendDrivenOptimisticUi.Rules

  @doc "The id of `event` pushed under `label` by a write to `record`, as `record` is now."
  @spec for(struct(), atom(), atom()) :: String.t()
  def for(%{__struct__: resource, id: id, updated_at: updated_at}, event, label) do
    Enum.join([Rules.type(resource), id, DateTime.to_iso8601(updated_at), event, label], ":")
  end

  @doc "The `{event, label}` of every push `resource` declares that has a record before the write."
  @spec declared(Ash.Resource.t()) :: [{atom(), atom()}]
  def declared(resource) do
    optimistic =
      for rule <- Info.rules(resource),
          identified?(resource, rule.action),
          event <- pushed_events(rule.effects),
          do: {event, rule.action}

    reacted =
      for reaction <- Info.reactions(resource),
          event <- pushed_events(reaction.effects),
          do: {event, reaction.event}

    Enum.uniq(optimistic ++ reacted)
  end

  @doc "Every declared push id of `record`: `%{event => %{label => id}}`."
  @spec for_record(struct()) :: %{atom() => %{atom() => String.t()}}
  def for_record(%{__struct__: resource} = record) do
    Enum.reduce(declared(resource), %{}, fn {event, label}, push_ids ->
      put_in(push_ids, [Access.key(event, %{}), label], __MODULE__.for(record, event, label))
    end)
  end

  @doc "Whether the pushes of `optimistic action` carry an id: its record exists before the write."
  @spec identified?(Ash.Resource.t(), atom()) :: boolean()
  def identified?(resource, action), do: Ash.Resource.Info.action(resource, action).type in [:update, :destroy]

  @doc "The JSON Logic variable path the compiled push reads its id from."
  @spec variable(atom(), atom()) :: String.t()
  def variable(event, label), do: "ctx.push_ids.#{event}.#{label}"

  defp pushed_events(effects) do
    Enum.flat_map(effects, fn
      %Push{event: event} -> [event]
      %Where{effects: nested} -> pushed_events(nested)
      _set -> []
    end)
  end
end
