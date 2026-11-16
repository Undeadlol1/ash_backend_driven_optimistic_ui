defmodule AshBackendDrivenOptimisticUi.Change do
  @moduledoc """
  Lets a change module describe its effect for the client, once, next to its
  code. The client cannot run Elixir, so without this every `optimistic` block
  of every action that uses the change repeats the effect as a `set`.

      defmodule MyApp.Changes.Bump do
        use Ash.Resource.Change
        use AshBackendDrivenOptimisticUi.Change

        @impl Ash.Resource.Change
        def change(changeset, opts, _context),
          do: Ash.Changeset.atomic_update(changeset, :count, expr(count + ^opts[:by]))

        @impl AshBackendDrivenOptimisticUi.Change
        def optimistic_sets(opts), do: [count: expr(count + ^opts[:by])]
      end

  `optimistic_sets/1` gets the opts the action passes
  (`change {MyApp.Changes.Bump, by: 2}`) and returns attributes with an
  expression or a literal. Each one becomes a derived `set` in every optimistic
  action that uses the change. A change guarded by `where` is skipped, and a
  `set` written in the rule for the same attribute wins. The values follow the
  rules of any `set`: no relationship, no actor, only functions the client can
  run. `optimistic` in tests fails when the description and the change disagree.
  """

  @callback optimistic_sets(opts :: keyword()) :: keyword()

  defmacro __using__(_opts) do
    quote do
      @behaviour AshBackendDrivenOptimisticUi.Change

      import Ash.Expr
    end
  end
end
