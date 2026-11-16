defmodule AshBackendDrivenOptimisticUi.NotOptimisticTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.NotOptimistic

  describe "GIVEN the reasons an action may give for staying without optimistic UI" do
    test "WHEN they are listed THEN they are exactly the documented five" do
      assert NotOptimistic.reasons() ==
               [
                 :ai_result,
                 :server_decides,
                 :background,
                 :admin,
                 :not_yet
               ]
    end
  end
end
