# What a rule may read

A rule runs on the client, so it can only read what the client holds. It is
checked and compiled when the resource compiles. If it reads
something a client cannot read, or uses a function the client cannot run,
compilation fails with a message that names the action.

## What you can read

| In the expression | Reads | Where |
| --- | --- | --- |
| `balance` | an attribute, calculation or aggregate of the same resource | `optimistic` and `on` |
| `arg(:cost)` | an argument of the action, or an attribute the action accepts | `optimistic` only |
| `^context(:key)` | a field of the record's `ctx` map, which the server fills (see [`ctx`](how-it-works.md#ctx)) | `optimistic` and `on` |
| `event(:key)` | a field of the pushed event | `on` only |
| `has_arg(:name)` | whether the input carries that key | `optimistic` only |

A `set` target must be an attribute or a public calculation of the same
resource.

## What you cannot read

- **Relationships.** `author.name` fails. Add a calculation or aggregate to
  the resource and read that.
- **The actor.** `^actor(:id)` fails. The client does not hold it.
- **Other records.** A rule sees the record it belongs to. A reaction (`on`)
  sees its own record and the event.

## Functions

| You write | The client runs |
| --- | --- |
| `+ - * /`, unary `-` | the same |
| `== !=` | the same, after a check that the sides that are not literals are not null (Ash gives nil, so false, when a side is nil) |
| `< > <= >=` | the same, each side that is not a number literal cast to a number with `+`, unless a side is text or a date (then no cast) |
| `a <> b` | `cat` (nested ones become one), each part that is not a text literal wrapped in `to_string` |
| `x in list` | `in`, after the same null check |
| `and`, `or`, `not` | `and`, `or`, `!` |
| `if(cond, then: a, else: b)` | `if` |
| `is_nil(x)` | `x == nil` |
| `abs(x)`, `round(x)`, `round(x, places)`, `to_string(x)`, `now()` | custom operations the client must add |
| `has_arg(:name)` | custom operator `has` |

Everything else is standard JSON Logic. `abs`, `round`, `to_string`, `now`
and `has` are the five custom operations; a client that evaluates rules
has to add them (see "What a client needs" in
[How it works](how-it-works.md)). `now` is the current UTC time as ISO 8601
text.

Two rules of the translator keep Ash behaviour on a standard evaluator.
Compared values are cast to numbers with `+`, because Ash sends decimals as
text and standard JSON Logic would compare two texts as text (`"10.5"` would
be smaller than `"9"`). Texts, dates and times compare as text, so nothing is
cast when a side is a text or date literal or an attribute or argument that
Ash sends as text. Joined values are wrapped in `to_string`, because
standard `cat` prints an empty value as `null` and you expect nothing.

Any other function, such as `contains` or `today()`,
fails compilation.

Decimals become floats in the rule. Atoms become strings.

## Names in the compiled rule

| Expression | JSON Logic variable |
| --- | --- |
| `balance` | `record.balance` |
| `arg(:cost)` | `input.cost` |
| `^context(:level_up_message)` | `ctx.level_up_message` |
| `event(:amount)` | `event.amount` |

A nested context path is dotted: `ctx.copy.title`.

## What is taken from the action

Before your declared effects, each rule gets `set` effects read from the
action:

- `change atomic_update(attr, expr)` becomes `set attr, expr`.
- `change set_attribute(attr, value)` becomes a `set` when `value` is a
  number, a string, an atom or `arg(...)`.
- A change module that implements `AshBackendDrivenOptimisticUi.Change`
  gives the sets that `optimistic_sets(opts)` returns, with the opts the
  action passes. They apply every time, and the same rules as any `set`
  hold: no relationship, no actor.
- For a create, every attribute in `accept` becomes `set attr, arg(attr)`, or
  the attribute's literal default when the input omits it. An attribute with a
  computed default is set only when the input carries it.
- For an update, every attribute in `accept` becomes the same set, inside
  `where expr(has_arg(attr))`: an update changes a field only when the input
  carries it.
- The options of `set_attribute` are followed: `new?: true` on a create takes
  the sent value, else the given one (on an update it is skipped), and
  `set_when_nil?: false` applies the set only when the value is not nil.

Derived sets are marked `"source": "derived"` in the rule, declared ones
`"declared"`. Changes that are a function or a module without `optimistic_sets/1`, and changes with a
`where:` guard, derive nothing, so a rule never claims more than the action
shows. If the same attribute is also declared, the declared `set` wins.
