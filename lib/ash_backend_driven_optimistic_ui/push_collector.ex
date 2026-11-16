defmodule AshBackendDrivenOptimisticUi.PushCollector do
  @moduledoc """
  A per-process list of the pushes sent while handling one request.

  `open/0` starts collecting in the calling process, every push sender calls
  `record/2`, and `drain/0` returns the pushes in send order and stops
  collecting. A push recorded in a process started for the request, such as
  the task Ash runs an action in under a deadline, reaches the collector of
  the nearest `$callers` ancestor that has one open. Pushes from any other
  process, or after the collector was drained, are dropped.

  `drain_reconciliation/1` is what any transport sends back with the answer:
  call `open/0` before the action runs, then put its result where the client
  reads it.
  """

  @key :push_collector
  @optimistic_ids_header "x-optimistic-ids"

  @doc "The request header, or metadata key, carrying the ids the client showed at once."
  @spec optimistic_ids_header() :: String.t()
  def optimistic_ids_header, do: @optimistic_ids_header

  @doc """
  Stops collecting and returns `%{"pushes" => pushes, "retracted" => ids}`, or
  `nil` when nothing was pushed and no optimistic id was sent. `header_values`
  are the values of the `x-optimistic-ids` request header, each a
  comma-separated list. An id is retracted when no push carries it as its
  `id` or `sync_cursor`.
  """
  @spec drain_reconciliation([String.t()]) :: map() | nil
  def drain_reconciliation(header_values) do
    pushes = drain()
    optimistic_ids = parse_optimistic_ids(header_values)

    if pushes == [] and optimistic_ids == [] do
      nil
    else
      %{"pushes" => pushes, "retracted" => optimistic_ids -- pushed_ids(pushes)}
    end
  end

  @spec open() :: :ok
  def open do
    Process.put(@key, [])
    :ok
  end

  @spec record(String.t(), map()) :: :ok
  def record(event, payload) do
    push = %{"event" => event, "payload" => payload}

    case Process.get(@key) do
      nil -> forward_to_collecting_caller(push)
      pushes -> Process.put(@key, [push | take_forwarded(pushes)])
    end

    :ok
  end

  @spec drain() :: [map()]
  def drain do
    case Process.delete(@key) do
      nil -> []
      pushes -> pushes |> take_forwarded() |> Enum.reverse()
    end
  end

  defp parse_optimistic_ids(header_values) do
    header_values
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp pushed_ids(pushes) do
    Enum.flat_map(pushes, fn %{"payload" => payload} ->
      for key <- [:id, "id", :sync_cursor, "sync_cursor"],
          value = Map.get(payload, key),
          is_binary(value),
          do: value
    end)
  end

  defp forward_to_collecting_caller(push) do
    case Enum.find(Process.get(:"$callers", []), &collecting?/1) do
      nil -> :ok
      collector -> send(collector, {@key, push})
    end
  end

  defp collecting?(pid) do
    match?({_, pushes} when is_list(pushes), Process.info(pid, {:dictionary, @key}))
  end

  defp take_forwarded(pushes) do
    receive do
      {@key, push} -> take_forwarded([push | pushes])
    after
      0 -> pushes
    end
  end
end
