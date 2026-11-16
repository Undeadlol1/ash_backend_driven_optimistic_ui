defmodule AshBackendDrivenOptimisticUi.Effect.Remove do
  @moduledoc """
  Takes the record out of the list the client holds of this resource: a destroy
  deletes it, an update can leave it where that list no longer shows it.
  """

  require AshBackendDrivenOptimisticUi.Effect

  AshBackendDrivenOptimisticUi.Effect.nested_list_effect(
    :remove,
    "Take the record out of the client's list of this resource.",
    ["remove()", "remove from: [:groups, :items]"],
    "A list nested inside the one record the client holds, as keys from its top: " <>
      "`{key, field: expr(...)}` steps into the rows of `key` whose `field` equals the value.",
    required: false
  )
end
