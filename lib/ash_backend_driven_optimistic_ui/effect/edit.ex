defmodule AshBackendDrivenOptimisticUi.Effect.Edit do
  @moduledoc """
  Applies the rule's sets to the record's own row in a list nested inside the
  one record the client holds, for an update of a row there:
  `edit from: [:meals, :ingredients]` finds the row by id on that path.
  """

  require AshBackendDrivenOptimisticUi.Effect

  AshBackendDrivenOptimisticUi.Effect.nested_list_effect(
    :edit,
    "Apply the rule's sets to the record's row in a list nested inside the one record the client holds.",
    ["edit from: [:meals, :ingredients]"],
    "The list the row is in, as keys from the top of the record: " <>
      "`{key, field: expr(...)}` steps into the rows of `key` whose `field` equals the value."
  )
end
