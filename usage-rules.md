# Rules for working with AshBackendDrivenOptimisticUi

AshBackendDrivenOptimisticUi is optimistic UI where the server writes the
rules. The server already sends the app a notification after each change
(an Ash notifier over the WebSocket). A rule describes that notification in
advance: the app downloads the rules at start, applies the matching rule the
moment the user taps, then compares it with the real notification when it
arrives and keeps the real data. The library is the server side; no client
is published yet.

- A resource must already send its changes to the app. Without a
  notification nothing confirms the guess, so do not add a rule.
- A `set` is a field as the notification will carry it; a `push` is another
  notification the action causes.
- Two kinds of effects. Properties (`set`, `insert`, `remove`, `edit`,
  `clear`) are corrected by the real record the server sends, so they need
  nothing extra. Events (`push`, answered by `on`) are one-time: they need an
  id, and a wrong one is only corrected by the list of pushes sent with the
  save's answer (`PushCollector.drain_reconciliation/1`).

## Setup

- Dependency: `{:ash_backend_driven_optimistic_ui, "~> 0.1"}`. With `igniter` in the
  deps, `mix igniter.install ash_backend_driven_optimistic_ui` adds it and does the
  config and formatter steps below.
- Config: `config :ash_backend_driven_optimistic_ui, otp_app: :my_app, pubsub: MyApp.PubSub`.
  Rules are collected from `config :my_app, ash_domains: [...]`. `pubsub` is
  read only by `AshBackendDrivenOptimisticUi.Test`.
- `phoenix` is needed only for the test helpers.
- Send two things to the client, over any transport: the rules (add
  `resource AshBackendDrivenOptimisticUi.RuleSet` to a domain and expose its
  `:rules` action with your API layer; do not write a route that returns
  `Registry.rules/0`; the client downloads them again when
  `Registry.version/0` changes) and, with the answer to each save, `PushCollector.drain_reconciliation/1`. Call
  `PushCollector.open/0` before the action. Do not build the payload by hand.
- Whatever sends pushes must call
  `AshBackendDrivenOptimisticUi.PushCollector.record/2`.

## `ctx` and event ids

- `^context(:name)` reads `ctx.name`: a map calculation named `ctx` on the
  resource, filled by the server, loaded by the client with the record. Put
  facts the client cannot work out there.
- A resource whose update or destroy rules `push` must put
  `push_ids: AshBackendDrivenOptimisticUi.PushId.for_record(record)` in its
  `ctx`. The compiled push reads its id from there.
- The server's real event must use the same id:
  `PushId.for(record_before_the_write, event, label)`, where `label` is the
  action (or, inside `on`, the answered event). Otherwise the client shows
  the event twice.
- Pushes in a create or generic action have no id.

## Declaring rules

- Add `extensions: [AshBackendDrivenOptimisticUi.Resource]` to
  `use Ash.Resource` and an `optimistic_ui` block:

  ```elixir
  optimistic_ui do
    optimistic :spend do
      set :balance, expr(balance - arg(:cost))
    end
  end
  ```

- `optimistic :action` takes a create, update, destroy or generic action of
  the same resource. One `optimistic` per action.
- Effects inside `optimistic`: `set`, `push`, `where`, and for lists
  `insert` (create only), `remove` (not create), `edit` (not create) and
  `clear`. Inside `on` only `set`, `push` and `where` are allowed.
- `set :attribute, value` sets an attribute or a public calculation of the
  same resource. `value` is an `expr(...)`, an `arg(...)` or a literal.
- `push :event, key: expr(...)` plays the same event the server's notifier
  sends. Never set `id:` in a push; ids are computed
  (`AshBackendDrivenOptimisticUi.PushId`).
- `where expr(...) do ... end` runs its effects only when the condition is
  true. `where` blocks can nest.
- `on :event do ... end` is this resource's reaction when another resource's
  rule pushes `event`. A reaction sees the record, the context and the event
  payload (`event(:key)`), never action arguments.
- Do not write a `set` the action already makes by itself. Readable
  `atomic_update(attr, expr)` and `set_attribute(attr, value)` changes, and
  every attribute a create accepts, become `set` effects on their own. A
  declared `set` for the same attribute replaces the derived one.

## What an expression may read

- The record's attributes, calculations and aggregates, `arg(:name)`
  (action arguments or accepted attributes; not inside `on`),
  `^context(:key)`, and inside `on` only `event(:key)`.
- Never relationships or the actor. The client does not hold them. To use
  related data, add a calculation or aggregate to the resource and read that.
- Only the functions `AshBackendDrivenOptimisticUi.Compiler` supports:
  `+ - * /`, comparisons, `<>`, `in`, `and`, `or`, `not`, `if`, `is_nil`,
  `abs`, `round`, `to_string`, `has_arg`. Anything else fails compilation.
- A wrong rule fails at compile time with a message naming the action. Fix
  the rule; do not catch the error.

## Actions with no rule

- Name every action that deliberately has no rule:
  `not_optimistic :create_from_image, because: :ai_result`.
- `because:` is one of `:ai_result`, `:server_decides`, `:background`,
  `:admin`, `:not_yet`. Pick the true reason; `:not_yet` means "should be
  optimistic, not converted yet".
- An action cannot have both `optimistic` and `not_optimistic`.
- Opaque change modules and conditional changes (`where:` on a change)
  derive nothing. If a change module changes data the client shows,
  implement `optimistic_sets/1` in it (`use AshBackendDrivenOptimisticUi.Change`)
  instead of repeating a `set` in each rule. For a conditional change,
  declare the `set`.

## Testing

- `use AshBackendDrivenOptimisticUi.Test` in an ExUnit module.
- Add one test that calls `assert_snapshots_current()`. It compares every
  compiled rule with `test/optimistic_ui/__snapshots__/<type>.<action>.json`
  and fails on a missing, changed or stale file, so nothing is added per
  action. The option `snapshot_dir:` points elsewhere.
- `optimistic MyApp.Wallet, :spend, wallet, %{cost: 5}, actor: user, topics: [...]`
  runs the real action and fails unless every `set` matches the real record
  and every `push` was broadcast on `topics:` with the same id and field
  values (extra broadcast fields are fine). Pass `topics:` whenever the rule
  pushes, so a renamed event field fails a test. It runs create, update and
  destroy actions, not generic ones. Pass `reacting: [records]` to
  check reactions too.
- After a deliberate rule change run `mix optimistic_ui.snapshot --update`,
  read the diff, commit it. Never update snapshots to silence a failure you
  do not understand.
- `mix optimistic_ui.explain wallet.award_xp` prints a rule and marks each
  `set` as derived or declared.
