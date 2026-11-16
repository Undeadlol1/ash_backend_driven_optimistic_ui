defmodule AshBackendDrivenOptimisticUi.TestHelpers do
  @moduledoc """
  Test helpers the AshBackendDrivenOptimisticUi tests share. Each used to be defined privately in
  several test files.
  """

  def record(name), do: %{"var" => "record.#{name}"}

  def input(name), do: %{"var" => "input.#{name}"}
end
