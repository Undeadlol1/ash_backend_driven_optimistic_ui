# Changelog

## Unreleased

- The evaluator now follows the full JSON Logic standard, checked by the official test suite. The translator casts compared values to numbers (`+`) and wraps joined values in `to_string`, so `<>` prints an empty value as nothing. A rule compares two texts as text only if written without the cast, which no Ash expression produces today.
- `AshBackendDrivenOptimisticUi.RuleSet`: a ready Ash resource whose `:rules` action returns the rules. List it in a domain and your API layer serves it like any other action; no hand-written route.
- `mix igniter.install ash_backend_driven_optimistic_ui` (and `mix ash_backend_driven_optimistic_ui.install`) does the
  setup: config and formatter import, then a notice names the two things the app sends to the client.
  `igniter` is now an optional dependency.
- `AshBackendDrivenOptimisticUi.PushCollector`: `open/0`, `record/2`, `drain/0` and `drain_reconciliation/1`
  carry the pushes and retractions of a request on any transport.
- The library's `.formatter.exs` exports the DSL's no-parens names. Adopters add
  `import_deps: [:ash_backend_driven_optimistic_ui]` instead of copying them. The library's own
  files are formatted, and `mix spark.formatter` regenerates the list.
- `assert_snapshots_current/1` in `AshBackendDrivenOptimisticUi.Test`: one test checks every rule's
  snapshot, so adopters add nothing per action.
- Docs: README, topic guides, a generated DSL reference and `usage-rules.md`.

## 0.1.0 - 2026-11-06

First release.

- `AshBackendDrivenOptimisticUi.Resource` extension with the `optimistic_ui` block
  (`optimistic`, `set`, `push`, `where`, `on`).
- Rules compiled to JSON Logic, served through `AshBackendDrivenOptimisticUi.Registry`.
- `mix optimistic_ui.explain` and `mix optimistic_ui.snapshot`.
- `AshBackendDrivenOptimisticUi.Test` helpers: snapshot checks and `optimistic`.
