# AshBackendDrivenOptimisticUi

Optimistic UI for [Ash](https://hexdocs.pm/ash). The app shows a change
the moment the user taps, using rules you write once, on the server.

## The problem

A user adds a todo. The app sends it to the server, waits for the answer,
and only then shows the new row. On a phone that wait can be a second
after every tap.

The usual fix is to show the row first and save it after. But then the
app has to know the server's rules: where the row goes, what else
changes. The rules get written twice, once on the server and once in the
app, and the two drift apart.

## What this library does

You write the rule next to the Ash action. The app downloads the rules
and applies one when the user taps. After the save, the server sends the
real data and the app keeps that.

- The change is on screen before the server answers.
- The rules live on the server. Change an action and every app gets the
  new rule without an app release.
- The server has the last word. If the save fails, or the server did
  something different, the app shows the server's data.

## Example

```elixir
defmodule MyApp.Todo do
  use Ash.Resource,
    domain: MyApp.Tasks,
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshBackendDrivenOptimisticUi.Resource]

  optimistic_ui do
    optimistic :create do
      insert at: :end
    end
  end

  pub_sub do
    module MyAppWeb.Endpoint
    prefix "todo"

    publish :create, "created"
  end
end
```

When the user adds a todo, the app puts it at the end of the list at
once, built from what the user typed.

The `pub_sub` block is plain Ash, not this library: after the save it
sends the saved todo to the app, and the app swaps its guess for it. A
resource that does not send its changes cannot have a rule.

The app gets the rules from one more line in the domain:

```elixir
defmodule MyApp.Tasks do
  use Ash.Domain

  resources do
    resource MyApp.Todo
    resource AshBackendDrivenOptimisticUi.RuleSet
  end
end
```

`RuleSet` has one action, `:rules`. Expose it with the API layer you
already use, like any other action. One piece is left, described in
[Send two things to the client](#send-two-things-to-the-client).

## Installation

With [Igniter](https://hexdocs.pm/igniter) in your deps, one command does
it:

```bash
mix igniter.install ash_backend_driven_optimistic_ui
```

It adds the dependency, writes the config and adds the formatter import.
Running it twice changes nothing. It then prints what is left for you: the
two things your app sends to the client.

### By hand

Add it to your deps:

```elixir
def deps do
  [
    {:ash_backend_driven_optimistic_ui, "~> 0.1"}
  ]
end
```

Add `import_deps: [:ash_backend_driven_optimistic_ui]` to your
`.formatter.exs`, so the formatter leaves the rules without parentheses.

Tell the library which app's domains to read:

```elixir
config :ash_backend_driven_optimistic_ui, otp_app: :my_app, pubsub: MyApp.PubSub
```

## Send two things to the client

The library does not care how your app talks to the client (HTTP, gRPC, a
channel, GraphQL). Your app carries two things over that transport.

**1. The rules.** Add one line to a domain:

```elixir
resources do
  resource AshBackendDrivenOptimisticUi.RuleSet
end
```

Then expose its `:rules` action with your API layer, like any other
action. The client downloads the rules at start, and again when the
version changes.

**2. What happened to the guesses.** With the answer to each save, send
what was pushed and which guesses did not happen. Call
`AshBackendDrivenOptimisticUi.PushCollector.open()` before the action. After
it, call
`AshBackendDrivenOptimisticUi.PushCollector.drain_reconciliation(header_values)`
with the values of the request header the client sends its ids in (its name
is `PushCollector.optimistic_ids_header/0`), and put the result in the answer. Whatever sends your pushes must call
`AshBackendDrivenOptimisticUi.PushCollector.record/2` for each one.

## What your app needs

- Resources that already send their changes to the app, usually through
  an Ash notifier over a WebSocket. That is how the app gets the real
  data after a guess.
- A client that runs the rules. None is published yet;
  [On the wire](documentation/topics/on-the-wire.md) says what one has to do.

## Usage

### Add or remove a row

```elixir
optimistic :create do
  insert at: :start
end

optimistic :destroy
```

A destroy rule with no effects takes the row out of the list.

### Change a field

```elixir
optimistic :rename do
  set :title, expr(arg(:title))
end
```

You can often leave this out: simple changes on the action, and the fields
it accepts, are added to the rule for you.

### Show a toast at once

```elixir
optimistic :complete do
  set :done, true
  push :xp_awarded, amount: 10
end
```

The app shows the "+10 XP" toast right away. When the server sends the
real one, the app knows it already showed it.

### Say why an action has no rule

```elixir
not_optimistic :create_from_image, because: :ai_result
```

For actions whose result the app can't know in advance.

More rules, with explanations, are in
[Examples](documentation/topics/examples.md).

One thing you still write twice, a `push`'s name and fields:
[How it works](documentation/topics/how-it-works.md#what-is-still-written-twice).

## Limits

- A rule only sees what the app has: the record and what the user typed.
  Not relationships, other records or the actor.
- Only simple maths and logic. Summing a list, for example, can't be a
  rule; that change waits for the server.
- A change module is read only if it describes itself with
  `optimistic_sets/1`. Otherwise write the `set` yourself.

## Learn more

- [How it works](documentation/topics/how-it-works.md): what happens
  between the tap and the server's answer.
- [On the wire](documentation/topics/on-the-wire.md): one tap, message by
  message, with the real JSON.
- [Examples](documentation/topics/examples.md): rules for common
  features.
- [What a rule may read](documentation/topics/expressions.md): fields,
  input and functions a rule can use.
- [How to test](documentation/topics/testing.md): check that a rule
  matches what the action really does.
- [DSL reference](documentation/dsls/DSL-AshBackendDrivenOptimisticUi.Resource.md):
  every option.

## For AI assistants

Point your coding agent at `usage-rules.md`, in the library folder next
to this README.

## License

MIT. See the `LICENSE` file in the library folder.
