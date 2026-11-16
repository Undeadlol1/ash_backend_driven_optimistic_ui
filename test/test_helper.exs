{:ok, _} =
  Supervisor.start_link([{Phoenix.PubSub, name: AshBackendDrivenOptimisticUi.TestPubSub}],
    strategy: :one_for_one
  )

ExUnit.start()
