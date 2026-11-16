# Changelog

## 0.1.0 — 2026-11-16

First release.

- `AshBackendDrivenOptimisticUi.Resource` extension with the `optimistic_ui` block:
  `optimistic` rules, `on` reactions and `not_optimistic` opt-outs, with the effects
  `set`, `push`, `where`, `insert`, `remove`, `edit` and `clear`.
- Rules are compiled to JSON Logic. The evaluator follows the full JSON Logic standard,
  checked by the official test suite, plus five documented custom operations.
- `AshBackendDrivenOptimisticUi.RuleSet`: a ready Ash resource whose `:rules` action returns
  the rules. List it in a domain and your API layer serves it like any other action.
- `AshBackendDrivenOptimisticUi.PushCollector` carries the pushes and retractions of a
  request on any transport.
- `mix igniter.install ash_backend_driven_optimistic_ui` does the setup.
- `mix optimistic_ui.explain` and `mix optimistic_ui.snapshot`.
- `AshBackendDrivenOptimisticUi.Test` helpers: `assert_snapshots_current/1` checks every
  rule's snapshot in one test, and `optimistic` runs a rule.
- The library's `.formatter.exs` exports the DSL's no-parens names; adopters add
  `import_deps: [:ash_backend_driven_optimistic_ui]`.
- Docs: README, topic guides, a generated DSL reference and `usage-rules.md`.
