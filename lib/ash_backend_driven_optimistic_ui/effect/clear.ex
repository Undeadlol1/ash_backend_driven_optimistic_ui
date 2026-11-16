defmodule AshBackendDrivenOptimisticUi.Effect.Clear do
  @moduledoc """
  Empties a list nested inside the one record the client holds, for an action
  that deletes every row of it at once: `clear from: [:messages]`.
  """

  require AshBackendDrivenOptimisticUi.Effect

  AshBackendDrivenOptimisticUi.Effect.nested_list_effect(
    :clear,
    "Empty a list nested inside the one record the client holds.",
    ["clear from: [:messages]"],
    "The list, as keys from the top of the record: " <>
      "`{key, field: expr(...)}` steps into the rows of `key` whose `field` equals the value."
  )
end
