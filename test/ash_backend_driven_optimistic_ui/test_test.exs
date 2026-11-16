defmodule AshBackendDrivenOptimisticUi.TestTest do
  use ExUnit.Case, async: true
  use AshBackendDrivenOptimisticUi.Test

  alias Ash.Error.Invalid
  alias AshBackendDrivenOptimisticUi.Test, as: OptimisticUiTest
  alias AshBackendDrivenOptimisticUi.TestSupport.ListItemResource
  alias AshBackendDrivenOptimisticUi.TestSupport.SampleResource
  alias Phoenix.Socket.Broadcast

  @snapshot_dir "test/ash_backend_driven_optimistic_ui/__snapshots__"

  defp record(attrs), do: SampleResource |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()

  defp xp_awarded_broadcast(topic), do: %Broadcast{topic: topic, event: "xp_awarded", payload: %{xp_amount: 7}}

  defp broadcast(topic, event, payload), do: %Broadcast{topic: topic, event: event, payload: payload}

  defp level_up_wallet do
    record(%{
      total_xp: Decimal.new(5),
      xp_to_next_level: Decimal.new(10),
      current_level: 1,
      ctx: %{"level_up_message" => "Well done"}
    })
  end

  defp tip_with_topic(topic, broadcasts) do
    wallet = record(%{balance: 10})
    jar = record(%{balance: 1})
    Enum.each(broadcasts, &send(self(), broadcast(topic, &1, %{amount: 4})))

    tip(wallet, jar, 4, reacting: [jar], topics: [topic])
  end

  defp tip(wallet, jar, amount, opts \\ []),
    do: OptimisticUiTest.check_rule(SampleResource, :tip, wallet, %{amount: amount, jar_id: jar.id}, opts)

  describe "GIVEN the optimistic UI test helper WHEN a record is converted to what the client sees" do
    test "THEN atoms become strings and nil and booleans stay as they are" do
      assert OptimisticUiTest.wire(%{status: :immediately, flag: true, none: nil}) ==
               %{"status" => "immediately", "flag" => true, "none" => nil}
    end

    test "THEN a loaded calculation travels with the record and an unloaded one is left out" do
      wallet = record(%{balance: 10})

      assert OptimisticUiTest.wire(wallet)["balance"] == 10
      refute Map.has_key?(OptimisticUiTest.wire(wallet), "spendable")
      assert OptimisticUiTest.wire(Ash.load!(wallet, :spendable))["spendable"] == 9
    end
  end

  describe "GIVEN the optimistic UI test helper WHEN the rule is evaluated without running the action" do
    test "THEN the sets and pushes are returned and the record is left unchanged" do
      wallet = record(%{balance: 10, current_level: 4})

      assert %{sets: %{"balance" => 5, "current_level" => 1}, pushes: []} =
               OptimisticUiTest.rules(SampleResource, :spend, wallet, %{cost: 5}, [])

      assert Ash.reload!(wallet).balance == 10
    end

    test "THEN each push is listed with its event and evaluated payload" do
      wallet = record(%{total_xp: Decimal.new(5), xp_to_next_level: Decimal.new(100)})

      assert %{pushes: [%{event: "xp_awarded", payload: %{"xp_amount" => 7.0}}]} =
               OptimisticUiTest.rules(
                 SampleResource,
                 :award_xp,
                 wallet,
                 %{xp_amount: Decimal.new(7)},
                 []
               )
    end

    test "THEN the context defaults to the record's own ctx field" do
      wallet = level_up_wallet()

      assert %{pushes: [_xp_awarded, %{event: "level_up", payload: %{"message" => "Well done"}}]} =
               OptimisticUiTest.rules(
                 SampleResource,
                 :award_xp,
                 wallet,
                 %{xp_amount: Decimal.new(10)},
                 []
               )
    end

    test "THEN an explicit ctx wins over the record's ctx field" do
      wallet = level_up_wallet()

      assert %{pushes: [_xp_awarded, %{payload: %{"message" => "Override"}}]} =
               OptimisticUiTest.rules(
                 SampleResource,
                 :award_xp,
                 wallet,
                 %{xp_amount: Decimal.new(10)},
                 ctx: %{"level_up_message" => "Override"}
               )
    end

    test "THEN a set on a calculation is optimistic from the record's other fields" do
      wallet = record(%{balance: 10})

      assert %{sets: %{"spendable" => 12}} =
               OptimisticUiTest.rules(SampleResource, :refund, wallet, %{amount: 3}, [])
    end
  end

  describe "GIVEN the optimistic UI test helper WHEN a destroy action runs" do
    test "THEN the record is destroyed for real and its push is checked" do
      wallet = record(%{balance: 3})
      send(self(), broadcast("wallet", "closed", %{balance: 3}))

      {destroyed, failures} =
        OptimisticUiTest.check_rule(SampleResource, :close, wallet, %{}, topics: ["wallet"])

      assert failures == []
      assert destroyed.id == wallet.id

      assert Ash.get(SampleResource, wallet.id, authorize?: false) ==
               {:error, %Invalid{}} or
               match?({:error, _}, Ash.get(SampleResource, wallet.id, authorize?: false))
    end
  end

  describe "GIVEN the optimistic UI test helper WHEN a rule runs on a list" do
    test "THEN an insert shows the new record from the input" do
      added = optimistic(ListItemResource, :add, nil, %{title: "Milk"})

      assert added.title == "Milk"
    end

    test "THEN a remove destroys the record for real" do
      item = ListItemResource |> Ash.Changeset.for_create(:add, %{title: "Milk"}) |> Ash.create!()

      optimistic(ListItemResource, :discard, item, %{})

      assert {:error, %Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(ListItemResource, item.id)
    end
  end

  describe "GIVEN the optimistic UI test helper WHEN a rule is asked whether it takes a row off the list" do
    test "THEN a remove takes the row off without running the action" do
      item = ListItemResource |> Ash.Changeset.for_create(:add, %{title: "Milk"}) |> Ash.create!()

      assert removes?(ListItemResource, :discard, item, %{})
      assert Ash.get!(ListItemResource, item.id).title == "Milk"
    end

    test "THEN a rule that only sets and pushes leaves the row, whichever way its where goes" do
      wallet = level_up_wallet()

      refute removes?(SampleResource, :award_xp, wallet, %{xp_amount: Decimal.new(20)})
      refute removes?(SampleResource, :award_xp, wallet, %{xp_amount: Decimal.new(1)})
    end
  end

  describe "GIVEN the optimistic UI test helper WHEN every snapshot is checked at once" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      rules = AshBackendDrivenOptimisticUi.Registry.rules()["rules"]
      AshBackendDrivenOptimisticUi.Snapshot.write(rules, dir)
      %{dir: dir, key: rules |> Map.keys() |> Enum.sort() |> hd()}
    end

    test "THEN snapshots that match every rule pass", %{dir: dir} do
      assert_snapshots_current(snapshot_dir: dir)
    end

    test "THEN the committed snapshots of the sample domain pass" do
      assert_snapshots_current(snapshot_dir: @snapshot_dir)
    end

    test "THEN a missing snapshot fails naming its rule and the rerun instruction", %{
      dir: dir,
      key: key
    } do
      File.rm!(Path.join(dir, key <> ".json"))

      error =
        assert_raise ExUnit.AssertionError, fn -> assert_snapshots_current(snapshot_dir: dir) end

      assert error.message =~ "missing"
      assert error.message =~ key
      assert error.message =~ "mix optimistic_ui.snapshot --update, review the diff, commit"
    end

    test "THEN a changed snapshot fails naming its rule", %{dir: dir, key: key} do
      File.write!(Path.join(dir, key <> ".json"), ~s({"effects": [], "reactions": []}))

      error =
        assert_raise ExUnit.AssertionError, fn -> assert_snapshots_current(snapshot_dir: dir) end

      assert error.message =~ "changed"
      assert error.message =~ key
    end

    test "THEN a snapshot without a rule fails naming it", %{dir: dir} do
      File.write!(Path.join(dir, "gone_resource.gone.json"), "{}")

      error =
        assert_raise ExUnit.AssertionError, fn -> assert_snapshots_current(snapshot_dir: dir) end

      assert error.message =~ "stale"
      assert error.message =~ "gone_resource.gone"
    end
  end

  describe "GIVEN the optimistic UI test helper WHEN the behaviour check runs" do
    test "THEN an update whose sets match the real record passes and returns the record" do
      wallet = record(%{balance: 10, current_level: 4})

      spent = optimistic(SampleResource, :spend, wallet, %{cost: 5})

      assert spent.balance == 5
      assert spent.current_level == 1
    end

    test "THEN a create shows its record from the input" do
      opened = optimistic(SampleResource, :open, nil, %{balance: 5, current_level: 7})

      assert opened.balance == 5
      assert opened.current_level == 1
    end

    test "THEN a set that the real action contradicts fails naming the attribute" do
      wallet = record(%{balance: 10, current_level: 4})

      error =
        assert_raise ExUnit.AssertionError, fn ->
          optimistic(SampleResource, :spend, wallet, %{cost: 3})
        end

      assert error.message =~ "balance"
      assert error.message =~ "but the action produced 3"
    end

    test "THEN pushes are not checked when no topics are given" do
      wallet = record(%{total_xp: Decimal.new(5), xp_to_next_level: Decimal.new(100)})

      awarded = optimistic(SampleResource, :award_xp, wallet, %{xp_amount: Decimal.new(7)})

      assert Decimal.equal?(awarded.total_xp, 12)
    end

    test "THEN an optimistic push that never reaches the topics fails naming the event" do
      wallet = record(%{total_xp: Decimal.new(5), xp_to_next_level: Decimal.new(100)})

      error =
        assert_raise ExUnit.AssertionError, fn ->
          optimistic(SampleResource, :award_xp, wallet, %{xp_amount: Decimal.new(7)}, topics: ["no_one_broadcasts_here"])
        end

      assert error.message =~ "xp_awarded"
      assert error.message =~ "no_one_broadcasts_here"
    end

    test "THEN an optimistic push that was broadcast passes" do
      topic = "optimistic_test:#{System.unique_integer([:positive])}"
      wallet = record(%{total_xp: Decimal.new(5), xp_to_next_level: Decimal.new(100)})
      send(self(), xp_awarded_broadcast(topic))

      assert {_record, []} =
               OptimisticUiTest.check_rule(
                 SampleResource,
                 :award_xp,
                 wallet,
                 %{xp_amount: Decimal.new(7)},
                 topics: [topic]
               )
    end

    test "THEN a broadcast field with another value fails naming the field and both values" do
      topic = "optimistic_test:#{System.unique_integer([:positive])}"
      wallet = record(%{total_xp: Decimal.new(5), xp_to_next_level: Decimal.new(100)})
      send(self(), broadcast(topic, "xp_awarded", %{xp_amount: 8}))

      assert {_record, [failure]} =
               OptimisticUiTest.check_rule(
                 SampleResource,
                 :award_xp,
                 wallet,
                 %{xp_amount: Decimal.new(7)},
                 topics: [topic]
               )

      assert failure =~ "xp_amount"
      assert failure =~ "7"
      assert failure =~ "8"
    end

    test "THEN a broadcast missing a field the rule pushes fails naming the field" do
      topic = "optimistic_test:#{System.unique_integer([:positive])}"
      wallet = record(%{total_xp: Decimal.new(5), xp_to_next_level: Decimal.new(100)})
      send(self(), broadcast(topic, "xp_awarded", %{}))

      assert {_record, [failure]} =
               OptimisticUiTest.check_rule(
                 SampleResource,
                 :award_xp,
                 wallet,
                 %{xp_amount: Decimal.new(7)},
                 topics: [topic]
               )

      assert failure =~ "xp_amount"
      assert failure =~ "missing"
    end

    test "THEN a number the server sends as text matches the same number" do
      topic = "optimistic_test:#{System.unique_integer([:positive])}"
      wallet = record(%{total_xp: Decimal.new(5), xp_to_next_level: Decimal.new(100)})
      send(self(), broadcast(topic, "xp_awarded", %{xp_amount: "7", message: "+7 XP"}))

      assert {_record, []} =
               OptimisticUiTest.check_rule(
                 SampleResource,
                 :award_xp,
                 wallet,
                 %{xp_amount: Decimal.new(7)},
                 topics: [topic]
               )
    end

    test "THEN a nested where that holds adds its sets and pushes to what is checked" do
      topic = "optimistic_test:#{System.unique_integer([:positive])}"

      wallet =
        record(%{total_xp: Decimal.new(5), xp_to_next_level: Decimal.new(10), current_level: 1})

      send(self(), xp_awarded_broadcast(topic))

      assert {_record, failures} =
               OptimisticUiTest.check_rule(
                 SampleResource,
                 :award_xp,
                 wallet,
                 %{xp_amount: Decimal.new(10)},
                 topics: [topic]
               )

      assert Enum.any?(failures, &(&1 =~ "current_level = 2"))
      assert Enum.any?(failures, &(&1 =~ "level_up"))
    end
  end

  describe "GIVEN the optimistic UI test helper WHEN a record carrying calculation dependency entries is converted" do
    test "THEN entries Ash keys by a tuple do not reach the client" do
      wallet = Ash.load!(record(%{balance: 10}), :spendable)

      with_dependency = %{
        wallet
        | calculations: Map.put(wallet.calculations, {:__calc_dep__, []}, 1)
      }

      assert OptimisticUiTest.wire(with_dependency) == OptimisticUiTest.wire(wallet)
    end
  end

  describe "GIVEN the optimistic UI test helper WHEN the reacting records are owned by the actor" do
    test "THEN the reacting record is reloaded as the actor" do
      owner = %{id: Ash.UUID.generate()}
      wallet = record(%{balance: 10})
      jar = record(%{balance: 1, owner_id: owner.id})

      assert {_record, []} = tip(wallet, jar, 4, reacting: [jar], actor: owner)
    end

    test "THEN the reload is refused without the owner as the actor" do
      wallet = record(%{balance: 10})
      jar = record(%{balance: 1, owner_id: Ash.UUID.generate()})

      assert_raise Invalid, fn -> tip(wallet, jar, 4, reacting: [jar]) end
    end
  end

  describe "GIVEN the optimistic UI test helper WHEN the behaviour check covers a calculation" do
    test "THEN a set on a calculation is compared with the calculation of the real record" do
      wallet = record(%{balance: 10})

      refunded = optimistic(SampleResource, :refund, wallet, %{amount: 3})

      assert refunded.balance == 13
    end
  end

  describe "GIVEN the optimistic UI test helper WHEN reacting records are given to the behaviour check" do
    test "THEN a reacting record changes the way the reaction answers" do
      wallet = record(%{balance: 10})
      jar = record(%{balance: 1})

      tipped =
        optimistic(SampleResource, :tip, wallet, %{amount: 4, jar_id: jar.id}, reacting: [jar])

      assert tipped.balance == 6
      assert Ash.reload!(jar).balance == 5
    end

    test "THEN a reacting record the real action left alone fails naming the reaction and the attribute" do
      wallet = record(%{balance: 10})
      jar = record(%{balance: 1})
      bystander = record(%{balance: 2})

      error =
        assert_raise ExUnit.AssertionError, fn ->
          optimistic(SampleResource, :tip, wallet, %{amount: 4, jar_id: jar.id}, reacting: [bystander])
        end

      assert error.message =~ "on tipped"
      assert error.message =~ "balance = 6"
    end

    test "THEN records of a type no reaction answers are ignored" do
      wallet = record(%{balance: 10})
      jar = record(%{balance: 1})

      assert {_record, []} =
               tip(wallet, jar, 4, reacting: [%AshBackendDrivenOptimisticUi.TestSupport.CycleResource{}])
    end

    test "THEN without reacting records the reactions are not checked" do
      wallet = record(%{balance: 10})
      jar = record(%{balance: 1})

      assert {_record, []} = tip(wallet, jar, 4)
    end

    test "THEN pushes made by a reaction are checked on the topics too" do
      topic = "optimistic_test:#{System.unique_integer([:positive])}"

      assert {_record, [failure]} = tip_with_topic(topic, ["tipped"])
      assert failure =~ "tip_received"
    end

    test "THEN pushes made by a reaction that were broadcast pass" do
      topic = "optimistic_test:#{System.unique_integer([:positive])}"

      assert {_record, []} = tip_with_topic(topic, ["tipped", "tip_received"])
    end
  end
end
