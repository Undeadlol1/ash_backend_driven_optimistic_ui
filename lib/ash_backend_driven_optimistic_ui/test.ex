defmodule AshBackendDrivenOptimisticUi.Test do
  @moduledoc """
  One-line checks that make refactoring an action safe. `use` this module
  inside an ExUnit module.

      assert_snapshots_current()

  in one test fails when any rule of the app has no committed snapshot, differs
  from it, or when a snapshot file names a rule that is gone. It covers every
  rule, so nothing is added per action. Fix it with `mix optimistic_ui.snapshot --update`,
  read the diff, commit. The `snapshot_dir:` option points elsewhere.

      wallet = optimistic MyApp.Wallet, :spend, wallet, %{cost: 5}, actor: user, topics: ["wallet:1"]

  evaluates the action's rule against the record and input, runs the real
  action, then fails unless every `set` of the rule equals the real record's
  value and every `push` of the rule was broadcast on one of `topics:` (its
  `id`, when it has one, included). Options: `actor:`, `ctx:`,
  `topics:` (default `[]`, which skips the push check) and `reacting:`
  (default `[]`), the records of other resources as the client holds them
  before the action. For each reaction of the rule that answers a type among
  them and an event the rule pushed, the reaction's `set`s are evaluated
  against that record, the pushed payload (`event`) and the record's own
  `ctx`, and must equal the reloaded record; its pushes are checked on
  `topics:` too. A `ctx:` left out reads the record's own `ctx` field.
  Returns the real record. Values are compared as the client sees them: JSON, decimals as floats.
  """

  alias Ash.Changeset
  alias Ash.Resource.Info
  alias AshBackendDrivenOptimisticUi.JsonLogic
  alias AshBackendDrivenOptimisticUi.Registry
  alias AshBackendDrivenOptimisticUi.Rules
  alias AshBackendDrivenOptimisticUi.Snapshot

  defmacro __using__(_opts) do
    quote do
      import AshBackendDrivenOptimisticUi.Test,
        only: [
          assert_snapshots_current: 0,
          assert_snapshots_current: 1,
          optimistic: 4,
          optimistic: 5,
          removes?: 4,
          removes?: 5
        ]
    end
  end

  @doc "Fails unless every rule of the app has its committed snapshot, unchanged, and no snapshot file is left without a rule."
  def assert_snapshots_current(opts \\ []) do
    dir = Snapshot.dir(opts)
    drift = Snapshot.drift(Registry.rules()["rules"], dir)

    if drift != %{missing: [], changed: [], stale: []} do
      ExUnit.Assertions.flunk(drift_message(drift, dir))
    end

    :ok
  end

  defp drift_message(drift, dir) do
    lists =
      for {label, keys} <- [
            {"missing (no snapshot file)", drift.missing},
            {"changed (the rule differs from its snapshot)", drift.changed},
            {"stale (a snapshot file without a rule)", drift.stale}
          ],
          keys != [],
          do: "#{label}: #{Enum.join(keys, ", ")}"

    "the rules the client gets differ from the snapshots in #{dir}:\n" <>
      Enum.join(lists, "\n") <>
      "\nrun mix optimistic_ui.snapshot --update, review the diff, commit"
  end

  @doc "Runs `action` for real and fails unless it did what its rule said it would; returns the real record."
  defmacro optimistic(resource, action, record, input, opts \\ []) do
    quote do
      {real_record, failures} =
        AshBackendDrivenOptimisticUi.Test.check_rule(
          unquote(resource),
          unquote(action),
          unquote(record),
          unquote(input),
          unquote(opts)
        )

      if failures != [], do: ExUnit.Assertions.flunk(Enum.join(failures, "\n"))
      real_record
    end
  end

  @doc """
  What `resource`'s `action` rule gives for `record` and `input`, without
  running the action: `%{sets: %{"attr" => value}, pushes: [%{event: "name", payload: map}]}`.
  Takes the options `optimistic` takes; a `ctx:` left out reads the record's own `ctx` field.
  """
  @spec rules(module(), atom(), struct() | nil, map() | keyword(), keyword()) :: %{
          sets: %{String.t() => term()},
          pushes: [%{event: String.t(), payload: map()}]
        }
  def rules(resource, action, record, input, opts \\ []) do
    {optimistic, _data} = evaluate(resource, action, record, input, opts)
    optimistic
  end

  @doc """
  What the reaction of `record`'s resource in `resource`'s `action` rule gives
  when that rule pushes `event` (`%{event: name, payload: map}`), read against
  `record` and its own `ctx`, without running anything. Same shape as `rules/5`.
  """
  @spec reaction(module(), atom(), struct(), %{event: String.t(), payload: map()}) :: %{
          sets: %{String.t() => term()},
          pushes: [%{event: String.t(), payload: map()}]
        }
  def reaction(resource, action, %{__struct__: reacting} = record, %{event: event, payload: payload}) do
    type = Rules.type(reacting)

    reaction =
      Enum.find(rule!(resource, action)["reactions"], &(&1["on"] == event and &1["type"] == type))

    record_data = wire(record)

    expected_effects(reaction["effects"], %{
      "record" => record_data,
      "event" => wire(payload),
      "ctx" => own_context(record_data, %{})
    })
  end

  @doc """
  Whether `resource`'s `action` rule takes `record` out of the client's list for
  `input`, without running the action: a `remove` the rule reaches through its
  `where`s. A rule of a generic action runs on every row the client shows, so
  asking this of each row tells which rows the client takes out.
  """
  @spec removes?(module(), atom(), struct(), map() | keyword(), keyword()) :: boolean()
  def removes?(resource, action, record, input, opts \\ []) do
    {_optimistic, data} = evaluate(resource, action, record, input, opts)
    resource |> rule!(action) |> Map.fetch!("effects") |> removes_in?(data)
  end

  defp removes_in?(effects, data) do
    Enum.any?(effects, fn
      %{"remove" => _options} ->
        true

      %{"where" => condition, "effects" => nested} ->
        JsonLogic.truthy?(JsonLogic.run(condition, data)) and removes_in?(nested, data)

      _effect ->
        false
    end)
  end

  @doc false
  def check_rule(resource, action, record, input, opts) do
    topics = Keyword.get(opts, :topics, [])
    actor = Keyword.get(opts, :actor)

    Enum.each(
      topics,
      &Phoenix.PubSub.subscribe(
        Application.fetch_env!(:ash_backend_driven_optimistic_ui, :pubsub),
        &1
      )
    )

    {optimistic, data} = evaluate(resource, action, record, input, opts)
    key = key(resource, action)
    real_record = run_action(resource, action, record, input, actor)

    {reaction_failures, reaction_pushes} =
      react(
        rule!(resource, action)["reactions"],
        Keyword.get(opts, :reacting, []),
        optimistic.pushes,
        data["ctx"],
        key,
        actor
      )

    {real_record,
     set_failures(optimistic.sets, real_wire(real_record, optimistic.sets, actor), key) ++
       reaction_failures ++ push_failures(optimistic.pushes ++ reaction_pushes, topics)}
  end

  defp evaluate(resource, action, record, input, opts) do
    record_data = wire(record || %{})

    data = %{
      "record" => record_data,
      "input" => wire(Map.new(input)),
      "ctx" => context(record_data, opts)
    }

    {resource |> rule!(action) |> Map.fetch!("effects") |> expected_effects(data), data}
  end

  defp context(record_data, opts) do
    case Keyword.fetch(opts, :ctx) do
      {:ok, ctx} -> wire(ctx)
      :error -> own_context(record_data, %{})
    end
  end

  defp own_context(%{"ctx" => %{} = ctx}, _fallback), do: ctx
  defp own_context(_record_data, fallback), do: fallback

  defp react(reactions, reacting, pushes, fallback_context, key, actor) do
    Enum.reduce(reactions, {[], []}, fn reaction, {failures, made} ->
      event = Enum.find(pushes ++ made, &(&1.event == reaction["on"]))
      targets = Enum.filter(reacting, &(Rules.type(&1.__struct__) == reaction["type"]))

      Enum.reduce(List.wrap(event && targets), {failures, made}, fn target, {failures, made} ->
        {target_failures, target_pushes} =
          react_on(reaction, event, target, fallback_context, key, actor)

        {failures ++ target_failures, made ++ target_pushes}
      end)
    end)
  end

  defp react_on(reaction, event, target, fallback_context, key, actor) do
    record_data = wire(target)

    data = %{
      "record" => record_data,
      "event" => event.payload,
      "ctx" => own_context(record_data, fallback_context)
    }

    optimistic = expected_effects(reaction["effects"], data)
    reloaded = target |> Ash.reload(actor: actor) |> ok!() |> real_wire(optimistic.sets, actor)

    {set_failures(optimistic.sets, reloaded, "#{key} -> on #{reaction["on"]}"), optimistic.pushes}
  end

  defp expected_effects(effects, data), do: effects |> effects_of(data) |> Map.update!(:sets, &Map.new/1)

  defp effects_of(effects, data) do
    Enum.reduce(effects, %{sets: [], pushes: []}, fn
      %{"set" => sets}, accumulated ->
        evaluated =
          Enum.map(sets, fn {attribute, rule} -> {attribute, JsonLogic.run(rule, data)} end)

        %{accumulated | sets: accumulated.sets ++ evaluated}

      %{"push" => %{"event" => event, "payload" => payload}}, accumulated ->
        push = %{
          event: event,
          payload: Map.new(payload, fn {key, rule} -> {key, JsonLogic.run(rule, data)} end)
        }

        %{accumulated | pushes: accumulated.pushes ++ [push]}

      %{"where" => condition, "effects" => nested}, accumulated ->
        if JsonLogic.truthy?(JsonLogic.run(condition, data)) do
          inner = effects_of(nested, data)
          %{sets: accumulated.sets ++ inner.sets, pushes: accumulated.pushes ++ inner.pushes}
        else
          accumulated
        end

      _insert_or_remove, accumulated ->
        accumulated
    end)
  end

  defp run_action(resource, action, record, input, actor) do
    case Info.action(resource, action).type do
      :create ->
        resource |> Changeset.for_create(action, input, actor: actor) |> Ash.create() |> ok!()

      :update ->
        record |> Changeset.for_update(action, input, actor: actor) |> Ash.update() |> ok!()

      :destroy ->
        record
        |> Changeset.for_destroy(action, input, actor: actor)
        |> Ash.destroy(return_destroyed?: true)
        |> ok!()
    end
  end

  defp ok!({:ok, record}), do: record
  defp ok!({:error, error}), do: raise(error)

  defp set_failures(sets, real, key) do
    for {attribute, optimistic} <- sets, real[attribute] != optimistic do
      "#{key} set #{attribute} = #{inspect(optimistic)} but the action produced #{inspect(real[attribute])}"
    end
  end

  defp push_failures(_pushes, []), do: []

  defp push_failures(pushes, topics) do
    {_unmatched, failures} =
      Enum.reduce(pushes, {received_pushes(), []}, fn %{event: event, payload: payload}, {received, failures} ->
        case Enum.find_index(received, &push_matches?(&1, event, payload)) do
          nil ->
            {received, failures ++ [missing_push_message(event, payload, topics, received)]}

          index ->
            {_event, received_payload} = Enum.at(received, index)

            {List.delete_at(received, index), failures ++ field_failures(event, payload, received_payload)}
        end
      end)

    failures
  end

  defp received_pushes(accumulated \\ []) do
    receive do
      %Phoenix.Socket.Broadcast{event: event, payload: payload} ->
        received_pushes([{event, wire(payload)} | accumulated])
    after
      0 -> Enum.reverse(accumulated)
    end
  end

  defp push_matches?({received_event, received_payload}, event, payload) do
    received_event == event and
      (not Map.has_key?(payload, "id") or received_payload["id"] == payload["id"])
  end

  defp field_failures(event, payload, received_payload) do
    for {field, value} <- payload,
        field != "id",
        failure = field_failure(field, value, received_payload) do
      "the rule pushes #{inspect(event)} with #{field} = #{inspect(value)}, but the broadcast #{failure}"
    end
  end

  defp field_failure(field, value, received_payload) do
    case Map.fetch(received_payload, field) do
      :error -> "is missing #{field}"
      {:ok, received} -> if !same_value?(value, received), do: "has #{inspect(received)}"
    end
  end

  # A server often sends numbers as text ("7") so decimals keep their digits.
  defp same_value?(value, value), do: true

  defp same_value?(value, received) when is_number(value) and is_binary(received), do: number(received) == value

  defp same_value?(value, received) when is_number(value) and is_number(received), do: value == received

  defp same_value?(_value, _received), do: false

  defp number(text) do
    case Float.parse(text) do
      {number, ""} -> number
      _not_a_number -> nil
    end
  end

  defp missing_push_message(event, payload, topics, received) do
    "the rule pushes #{inspect(event)} #{inspect(payload)} was not broadcast on #{inspect(topics)}; " <>
      "received #{inspect(received)}"
  end

  defp rule!(resource, action) do
    key = key(resource, action)

    case resource |> domains_with_reactions() |> Registry.rules() |> get_in(["rules", key]) do
      nil ->
        raise ArgumentError,
              "#{inspect(resource)} has no rule for #{inspect(action)} (#{key})"

      rule ->
        rule
    end
  end

  defp domains_with_reactions(resource) do
    domain = Info.domain(resource)
    app_domains = Registry.app_domains()

    if domain in app_domains, do: app_domains, else: [domain]
  end

  defp key(resource, action), do: "#{Rules.type(resource)}.#{action}"

  defp real_wire(record, sets, actor) do
    computed =
      sets
      |> Map.keys()
      |> Enum.map(&String.to_existing_atom/1)
      |> Enum.reject(&Info.attribute(record.__struct__, &1))

    record |> load_computed(computed, actor) |> wire()
  end

  defp load_computed(record, [], _actor), do: record

  defp load_computed(record, computed, actor), do: record |> Ash.load(computed, actor: actor) |> ok!()

  @doc false
  def wire(%Decimal{} = decimal), do: Decimal.to_float(decimal)

  def wire(%{__struct__: module} = struct), do: wire_struct(Info.resource?(module), struct)

  def wire(%{} = map), do: Map.new(map, fn {key, value} -> {to_string(key), wire(value)} end)
  def wire(list) when is_list(list), do: Enum.map(list, &wire/1)
  def wire(atom) when is_atom(atom) and atom not in [nil, true, false], do: Atom.to_string(atom)
  def wire(other), do: other

  defp wire_struct(true, record) do
    resource = record.__struct__
    attributes = Map.new(Info.attributes(resource), &{&1.name, Map.get(record, &1.name)})

    loaded =
      for %{name: name} <- Info.public_fields(resource),
          value <- [Map.get(record, name)],
          not match?(%Ash.NotLoaded{}, value),
          into: %{},
          do: {name, value}

    wire(
      Enum.reduce(
        [loaded, named_values(record.calculations), named_values(record.aggregates)],
        attributes,
        &Map.merge(&2, &1)
      )
    )
  end

  defp wire_struct(false, struct), do: struct |> Jason.encode!() |> Jason.decode!()

  defp named_values(values), do: Map.filter(values, fn {name, _value} -> is_atom(name) end)
end
