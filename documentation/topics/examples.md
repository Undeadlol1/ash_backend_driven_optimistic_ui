# Examples

Each example is the `optimistic_ui` block for a common app feature, with the
action it belongs to. Names are made up; swap in yours.

## A balance goes down

```elixir
optimistic_ui do
  optimistic :spend do
    set :balance, expr(balance - arg(:cost))
  end
end

actions do
  update :spend do
    require_atomic? false
    argument :cost, :integer, allow_nil?: false
    change atomic_update(:balance, expr(balance - ^arg(:cost)))
  end
end
```

The action already says `balance - cost`, so the `set` is optional: the
library derives it. Write it when you want the rule to be visible in the
block. A declared `set` replaces the derived one for the same attribute.

## A rule that sets an attribute the action does not show

When the action uses a change module, the library cannot read it. Declare
what it does:

```elixir
optimistic :award_xp do
  set :total_xp, expr(total_xp + arg(:xp_amount))
end
```

## A level-up only when the XP is enough

```elixir
optimistic :award_xp do
  push :xp_awarded, xp_amount: expr(arg(:xp_amount))

  where expr(arg(:xp_amount) >= xp_to_next_level) do
    set :current_level, expr(current_level + 1)
    push :level_up, message: expr(^context(:level_up_message))
  end
end
```

The `push` tells the client to show the event the server will send, such as a
toast, at once. The `where` runs its effects only when the condition is true.
`message` is read from the record's `ctx`, which the server fills, because the
client cannot translate it. See [How it works](how-it-works.md#ctx).

## Another resource reacts to an event

```elixir
# in the wallet resource
optimistic_ui do
  on :level_up do
    set :balance, expr(balance + 1)
  end
end
```

When any rule pushes `level_up`, the client also applies this `on` to its
wallet record. Reactions see their record, its `ctx` and the event payload
(`event(:key)`). They do not see action arguments.

```elixir
on :tipped do
  set :balance, expr(balance + event(:amount))
  push :tip_received, amount: expr(event(:amount))
end
```

A reaction can push too. Each `{event, resource}` pair runs once per rule,
so two reactions that push each other's events end instead of looping.

## A change module

```elixir
defmodule MyApp.Changes.Bump do
  use Ash.Resource.Change
  use AshBackendDrivenOptimisticUi.Change

  @impl Ash.Resource.Change
  def change(changeset, opts, _context),
    do: Ash.Changeset.atomic_update(changeset, :count, expr(count + ^opts[:by]))

  @impl AshBackendDrivenOptimisticUi.Change
  def optimistic_sets(opts), do: [count: expr(count + ^opts[:by])]
end
```

The app cannot run a change module, so it cannot see what it does.
`optimistic_sets/1` says it once, next to the code. Every optimistic action
that uses `change {MyApp.Changes.Bump, by: 2}` gets `set :count, expr(count + 2)`,
marked derived. A `where:` on the change turns this off.

## Only change a field the caller sent

```elixir
optimistic :retitle do
  where expr(has_arg(:title)) do
    set :title, expr(arg(:title))
  end
end
```

`has_arg` is true when the input has the key, even if its value is `nil`.

## Add a row to a list

A create can put the new record into the list the client holds:

```elixir
optimistic :add do
  insert at: :start
end
```

The record is built from the rule's sets. For a create, every attribute the
action accepts becomes a derived `set`, so `accept [:title]` is enough. The
client gives the row a temporary id until the saved record replaces it.

`at:` is `:start`, `:end` or `{:sorted_by, :title}`. The last one puts the
row before the first row whose `title` sorts after its own, for a list the
server orders by `title`.

## Add a row to a list inside another record

When the client holds one record with lists inside it, point at the list
with `into:`:

```elixir
optimistic :add_to_group do
  insert at: :end, into: [{:groups, id: expr(arg(:group_id))}, :items]
end
```

Read the path as "`groups`, the one whose `id` equals `group_id`, then its
`items`". A plain key keeps all rows; a `{key, field: expr(...)}` step keeps
only the rows whose `field` equals the value. The path must end in the key
of the list.

## Remove, edit and clear

```elixir
optimistic :discard do
  remove()
end

optimistic :discard_from_group do
  remove from: [:groups, :items]
end

optimistic :retitle_in_group do
  edit from: [:groups, :items]
  set :title, expr(arg(:title))
end

optimistic :discard_all do
  clear from: [:groups, :items]
end
```

- A destroy rule with no effects is `remove()`: `optimistic :discard` is enough.
- `remove` takes the record out of its list. It works for a destroy, or for
  an update after which the list no longer shows the record (put it behind a
  `where`).
- `edit` applies the rule's sets to the record's own row in a nested list.
- `clear` empties a nested list, for an action that deletes every row at
  once. It is often a generic action.
- `insert` is for creates only. `remove` and `edit` are not allowed in a
  create, because the row is not in the list yet.

## An action that is not optimistic

```elixir
not_optimistic :create_from_image, because: :ai_result
not_optimistic :sync_contacts, because: :background
```

Pick the reason that is true: `:ai_result`, `:server_decides`,
`:background`, `:admin` or `:not_yet`. Clients never see it. Tools read it
with `AshBackendDrivenOptimisticUi.Info.not_optimistic/1`, so you can list
which actions have no rule and why.
