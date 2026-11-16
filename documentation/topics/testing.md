# How to test with AshBackendDrivenOptimisticUi

Two checks keep rules honest. One notices when a rule changes. The other
runs the real action and compares it with the rule.

The examples use a wallet with a `spend` action:

```elixir
optimistic_ui do
  optimistic :spend do
    set :balance, expr(balance - arg(:cost))
  end
end
```

## Set up

```elixir
defmodule MyApp.WalletOptimisticTest do
  use ExUnit.Case, async: true
  use AshBackendDrivenOptimisticUi.Test
end
```

`use` adds `assert_snapshots_current`, `optimistic` and `removes?`. The
`optimistic` check subscribes to PubSub, so it needs `phoenix` in the test
environment and `pubsub:` in the config (see the README).

## Notice a rule change

```elixir
test "every rule matches its snapshot" do
  assert_snapshots_current()
end
```

One test covers every rule, so nothing is added per action. It compares each
compiled rule, reactions included, with
`test/optimistic_ui/__snapshots__/<type>.<action>.json`. It fails and lists
the rules whose file is missing or different, and the files that have no rule.
Pass `snapshot_dir: "..."` to read from elsewhere.

When the change is on purpose:

```
mix optimistic_ui.snapshot --update
```

Read the diff, then commit it. The task rewrites every snapshot and deletes
files whose rule is gone. `mix optimistic_ui.snapshot` without `--update`
exits non-zero and lists missing, changed and stale files, so it also works
as a CI check. `--dir` points at another directory.

## Check the rule against the real action

```elixir
test "spend does what its rule says" do
  wallet = create_wallet(balance: 10)

  wallet =
    optimistic MyApp.Wallet, :spend, wallet, %{cost: 5},
      actor: user,
      topics: ["wallet:#{wallet.id}"]

  assert wallet.balance == 5
end
```

`optimistic` evaluates the rule against the record and the input, runs the
real action, and fails unless every `set` equals the real record's value. It
returns the real record. Values are compared the way a client sees them:
JSON, with decimals as floats.

Options:

- `actor:` the actor for the real action.
- `ctx:` the `ctx` map the rule reads. Left out, it reads the record's own `ctx`
  attribute.
- `topics:` PubSub topics to listen on. Every `push` of the rule must be
  broadcast on one of them, with the same `id` (if it has one) and the
  same value for every field the rule pushes. The broadcast may have more
  fields; a number sent as text matches the number. Left out
  (`[]`), the push check is skipped.
- `reacting:` records of other resources, as the client holds them before the
  action. For each reaction of the rule that answers one of those types and
  an event the rule pushed, the reaction's sets are evaluated and compared
  with the reloaded record, and its pushes are checked on `topics:`.

`optimistic` can run create, update and destroy actions. It does not run
generic actions; check those with `rules/5` and `removes?`.

## Look at a rule without running anything

These return data and change nothing:

- `AshBackendDrivenOptimisticUi.Test.rules/5` gives
  `%{sets: %{"balance" => 5}, pushes: [...]}` for a record and input.
- `AshBackendDrivenOptimisticUi.Test.reaction/4` gives the same for a
  reaction.
- `removes?(resource, action, record, input)` says whether the rule takes
  the record out of the list. A generic action's rule runs on every row the
  client shows, so asking it of each row tells which rows go.

## Read a rule

```
mix optimistic_ui.explain wallet.award_xp
```

Prints the rule, one effect per line, then the reactions that follow its
pushes. Each `set` is marked `[derived]` or `[declared]`. An unknown key
fails and lists the known ones.
