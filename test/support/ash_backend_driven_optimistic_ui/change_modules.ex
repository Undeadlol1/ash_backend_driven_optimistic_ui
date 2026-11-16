defmodule AshBackendDrivenOptimisticUi.TestSupport.Bump do
  @moduledoc "Adds `by:` to `count` and says so for the client."

  use Ash.Resource.Change
  use AshBackendDrivenOptimisticUi.Change

  @impl Ash.Resource.Change
  def change(changeset, opts, _context) do
    Ash.Changeset.force_change_attribute(
      changeset,
      :count,
      Ash.Changeset.get_attribute(changeset, :count) + opts[:by]
    )
  end

  @impl AshBackendDrivenOptimisticUi.Change
  def optimistic_sets(opts), do: [count: expr(count + ^opts[:by])]
end

defmodule AshBackendDrivenOptimisticUi.TestSupport.Silent do
  @moduledoc "Adds one to `count` and does not describe it."

  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(
      changeset,
      :count,
      Ash.Changeset.get_attribute(changeset, :count) + 1
    )
  end
end

defmodule AshBackendDrivenOptimisticUi.TestSupport.Label do
  @moduledoc "Sets `title` to a fixed text and says so for the client."

  use Ash.Resource.Change
  use AshBackendDrivenOptimisticUi.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context), do: Ash.Changeset.force_change_attribute(changeset, :title, "labelled")

  @impl AshBackendDrivenOptimisticUi.Change
  def optimistic_sets(_opts), do: [title: "labelled"]
end

defmodule AshBackendDrivenOptimisticUi.TestSupport.Liar do
  @moduledoc "Adds one to `count` but tells the client it adds two."

  use Ash.Resource.Change
  use AshBackendDrivenOptimisticUi.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(
      changeset,
      :count,
      Ash.Changeset.get_attribute(changeset, :count) + 1
    )
  end

  @impl AshBackendDrivenOptimisticUi.Change
  def optimistic_sets(_opts), do: [count: expr(count + 2)]
end

defmodule AshBackendDrivenOptimisticUi.TestSupport.FromOwner do
  @moduledoc "Describes itself with a relationship, which the client does not hold."

  use Ash.Resource.Change
  use AshBackendDrivenOptimisticUi.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context), do: changeset

  @impl AshBackendDrivenOptimisticUi.Change
  def optimistic_sets(_opts), do: [count: expr(owner.count)]
end

defmodule AshBackendDrivenOptimisticUi.TestSupport.Clocked do
  @moduledoc "Describes itself with a function the client cannot run."

  use Ash.Resource.Change
  use AshBackendDrivenOptimisticUi.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context), do: changeset

  @impl AshBackendDrivenOptimisticUi.Change
  def optimistic_sets(_opts), do: [count: expr(today())]
end
