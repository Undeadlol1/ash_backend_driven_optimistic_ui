# What AshBackendDrivenOptimisticUi is

**An Ash extension that lets an app show a change before the server
answers.** The server declares what each write changes; clients download
those rules and apply them the moment the user taps. Read this before you
describe, review, redesign or document it.

## The goal

The developer does as little as possible. A rule is a line or two on the
resource, next to the action it describes. Whatever the library can work out
by itself, it does.

## Rules the code follows

- **Everything goes through Ash.** The rules are served by an Ash action
  (`RuleSet`), so any API layer the app already has can expose them.
- **No transport code.** Nothing here knows about Plug, Phoenix controllers,
  HTTP or WebSockets. `phoenix` is an optional dependency for the test
  helpers only.
- **The server decides, the client only runs rules.** A client needs a
  standard JSON Logic evaluator plus the documented custom operations.
- **JSON Logic follows the standard.** Ash-specific behaviour belongs in the
  compiler, not in the evaluator.
- **Nothing is guessed.** An action is optimistic only when a rule says so,
  or is marked `not_optimistic` with a reason.

## Do not

- Add a plug, a controller, a router or any other web-layer code.
- Suggest Phoenix or LiveView as the answer. The library works on Ash alone.
- Add options or abstractions nobody asked for.
