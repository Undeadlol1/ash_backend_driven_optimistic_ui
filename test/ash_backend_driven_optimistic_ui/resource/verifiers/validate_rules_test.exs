defmodule AshBackendDrivenOptimisticUi.Resource.Verifiers.ValidateRulesTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.TestSupport.SampleDomain
  alias AshBackendDrivenOptimisticUi.TestSupport.SampleResource
  alias Spark.Error.DslError

  require Spark.Test

  defp define_resource(optimistic_ui_block) do
    resource_name = Module.concat(__MODULE__, "Resource#{System.unique_integer([:positive])}")

    resource_body =
      quote do
        use Ash.Resource,
          domain: SampleDomain,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshBackendDrivenOptimisticUi.Resource]

        ets do
          private?(true)
        end

        unquote(optimistic_ui_block)

        attributes do
          uuid_primary_key(:id)
          attribute(:balance, :integer, public?: true)
        end

        relationships do
          belongs_to(:owner, SampleResource)
        end

        calculations do
          calculate(:doubled_balance, :integer, expr(balance * 2))
          calculate(:shown_balance, :integer, expr(balance), public?: true)
        end

        actions do
          defaults([:read])

          create :open do
            accept([:balance])
          end

          update :spend do
            argument(:cost, :integer)
          end

          destroy(:close)

          action :announce, :string do
            run(fn _input, _context -> {:ok, "announced"} end)
          end
        end
      end

    Module.create(
      resource_name,
      Macro.prewalk(resource_body, &as_written_in_source/1),
      Macro.Env.location(__ENV__)
    )
  end

  defp as_written_in_source({name, meta, context}) when is_atom(name) and is_atom(context), do: {name, meta, nil}

  defp as_written_in_source(node), do: node

  defp verifier_errors(optimistic_ui_block) do
    dsl_errors_result =
      Spark.Test.dsl_errors do
        define_resource(optimistic_ui_block)
      end

    Enum.flat_map(dsl_errors_result, fn {_resource, errors} -> errors end)
  end

  defp open_error(effect) do
    assert [%DslError{path: [:optimistic_ui, :optimistic, :open]} = error] =
             verifier_errors(
               quote do
                 optimistic_ui do
                   optimistic :open do
                     unquote(effect)
                   end
                 end
               end
             )

    error
  end

  defp spend_error(effect) do
    assert [%DslError{path: path} = error] =
             verifier_errors(
               quote do
                 optimistic_ui do
                   optimistic :spend do
                     unquote(effect)
                   end
                 end
               end
             )

    assert path == [:optimistic_ui, :optimistic, :spend]
    error
  end

  describe "GIVEN the optimistic UI rules verifier WHEN a rule block is given to verify" do
    test "THEN a valid block compiles, with references to calculations included" do
      assert [] ==
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :spend do
                       set(:balance, expr(doubled_balance - arg(:cost)))
                     end
                   end
                 end
               )
    end

    test "THEN a generic action passes" do
      assert [] ==
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :announce do
                       push(:announced, balance: expr(balance))
                     end
                   end
                 end
               )
    end

    test "THEN a set on a public calculation passes" do
      assert [] ==
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :spend do
                       set(:shown_balance, expr(balance - arg(:cost)))
                     end
                   end
                 end
               )
    end

    test "THEN an insert in a create and a remove in a destroy pass" do
      assert [] ==
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :open do
                       insert(at: :end)
                     end

                     optimistic :close do
                       remove()
                     end
                   end
                 end
               )
    end

    test "THEN an insert outside a create is rejected" do
      error = spend_error(quote(do: insert(at: :start)))

      assert error.message =~ "`insert` adds the new record to a list; only a create makes one"
    end

    test "THEN a remove in an update passes, for a record that leaves the list it is shown in" do
      assert [] ==
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :spend do
                       remove()
                     end
                   end
                 end
               )
    end

    test "THEN an insert into a nested list passes when its match reads an argument of the action" do
      assert [] ==
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :open do
                       insert(at: :end, into: [{:accounts, id: expr(arg(:balance))}, :entries])
                     end
                   end
                 end
               )
    end

    test "THEN a nested list path whose match reads an unknown argument is rejected" do
      assert [%DslError{} = error] =
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :open do
                       insert(at: :end, into: [{:accounts, id: expr(arg(:account_id))}, :entries])
                     end
                   end
                 end
               )

      assert error.message =~ ":account_id is not an argument of :open"
    end

    test "THEN a nested list path that ends in a match instead of the list is rejected" do
      error = spend_error(quote(do: remove(from: [:accounts, {:entries, id: expr(balance)}])))

      assert error.message =~ "must end in the key of the list"
    end

    test "THEN a nested list path with a step that is neither a key nor a match is rejected" do
      error = spend_error(quote(do: remove(from: [:accounts, "entries", :items])))

      assert error.message =~ ~s("entries" is not a path step)
    end

    test "THEN a remove in a create is rejected" do
      error = open_error(quote(do: remove()))

      assert error.message =~ "`remove` takes a record out of a list; a create has none there yet"
    end

    test "THEN an edit of a nested row and a set guarded by has_arg pass in an update" do
      assert [] ==
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :spend do
                       edit(from: [:accounts, :entries])

                       where expr(has_arg(:cost)) do
                         set(:balance, expr(arg(:cost)))
                       end
                     end
                   end
                 end
               )
    end

    test "THEN an edit in a create is rejected" do
      error = open_error(quote(do: edit(from: [:accounts, :entries])))

      assert error.message =~
               "`edit` changes a row already in a list; a create has none there yet"
    end

    test "THEN has_arg of an unknown argument is rejected" do
      error = spend_error(quote(do: where(expr(has_arg(:tip)), do: set(:balance, 1))))

      assert error.message =~ ":tip is not an argument of :spend"
    end

    test "THEN a sorted insert by an attribute and a clear in a generic action pass" do
      assert [] ==
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :open do
                       insert(at: {:sorted_by, :balance})
                     end

                     optimistic :announce do
                       clear(from: [:accounts, :entries])
                     end
                   end
                 end
               )
    end

    test "THEN a sorted insert by a field the record does not have is rejected" do
      assert [%DslError{} = error] =
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :open do
                       insert(at: {:sorted_by, :nickname})
                     end
                   end
                 end
               )

      assert error.message =~
               "`insert` sorts by :nickname, which is not an attribute of this resource"
    end

    test "THEN a clear whose path does not end in a list is rejected" do
      error = spend_error(quote(do: clear(from: [{:entries, id: expr(balance)}])))

      assert error.message =~ "must end in the key of the list"
    end

    test "THEN a set on a calculation that is not public is rejected" do
      error = spend_error(quote(do: set(:doubled_balance, 1)))

      assert error.message =~ ~r/:doubled_balance is not an attribute or public calculation/
    end

    test "THEN an event inside a reaction passes" do
      assert [] ==
               verifier_errors(
                 quote do
                   optimistic_ui do
                     on :tipped do
                       set(:balance, expr(balance + event(:amount)))
                     end
                   end
                 end
               )
    end

    test "THEN an event inside an optimistic is rejected" do
      error = spend_error(quote(do: set(:balance, expr(balance + event(:amount)))))

      assert error.message =~ ~r/event\/1 only works inside `on`/
    end

    test "THEN a push that writes its own id is rejected" do
      error = spend_error(quote(do: push(:spent, id: "spent:1", price: 1)))

      assert error.message =~ "`push :spent` must not set `id:`"
      assert error.message =~ "ctx.push_ids"
    end

    test "THEN a push that writes its own id inside a nested where in a reaction is rejected" do
      assert [%DslError{path: [:optimistic_ui, :on, :tipped], message: message}] =
               verifier_errors(
                 quote do
                   optimistic_ui do
                     on :tipped do
                       where expr(balance > 0) do
                         push(:tip_received, id: expr("tip:" <> balance))
                       end
                     end
                   end
                 end
               )

      assert message =~ "`push :tip_received` must not set `id:`"
    end

    test "THEN an action the resource does not have is rejected" do
      assert [%DslError{path: path, message: message}] =
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :nope do
                       set(:balance, 1)
                     end
                   end
                 end
               )

      assert message =~ ~r/no action :nope/
      assert path == [:optimistic_ui, :optimistic, :nope]
    end

    test "THEN a read action is rejected" do
      assert [%DslError{path: path, message: message}] =
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :read do
                       set(:balance, 1)
                     end
                   end
                 end
               )

      assert message =~ ~r/create, update, destroy or generic action/
      assert path == [:optimistic_ui, :optimistic, :read]
    end

    test "THEN a set on an attribute the resource does not have is rejected" do
      assert [%DslError{path: path, message: message}] =
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :spend do
                       set(:missing, 1)
                     end
                   end
                 end
               )

      assert message =~ ~r/:missing is not an attribute/
      assert path == [:optimistic_ui, :optimistic, :spend]
    end

    test "THEN an argument the action does not take is rejected, even inside a nested where" do
      assert [%DslError{path: path, message: message}] =
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :spend do
                       where expr(balance > 0) do
                         push(:spent, price: expr(arg(:price)))
                       end
                     end
                   end
                 end
               )

      assert message =~ ~r/:price is not an argument of :spend/
      assert path == [:optimistic_ui, :optimistic, :spend]
    end

    test "THEN an argument buried in not, and, if and calls is rejected" do
      error =
        spend_error(quote(do: set(:balance, expr(not (balance > 1 and if(balance, do: ^arg(:price), else: 0))))))

      assert error.message =~ ~r/:price is not an argument of :spend/
    end

    test "THEN an argument inside a list of expressions is rejected" do
      error = spend_error(quote(do: set(:balance, expr(balance in [1, ^arg(:price)]))))

      assert error.message =~ ~r/:price is not an argument of :spend/
    end

    test "THEN an argument inside a reaction is rejected" do
      assert [%DslError{path: path, message: message}] =
               verifier_errors(
                 quote do
                   optimistic_ui do
                     on :level_up do
                       set(:balance, expr(balance + arg(:cost)))
                     end
                   end
                 end
               )

      assert message =~ ~r/reactions have no action arguments/
      assert path == [:optimistic_ui, :on, :level_up]
    end

    test "THEN a reference to a field the resource does not have is rejected" do
      error = spend_error(quote(do: set(:balance, expr(ghost + 1))))

      assert error.message =~ ~r/:ghost is not an attribute, calculation or aggregate/
    end

    test "THEN a reference through a relationship is rejected" do
      error = spend_error(quote(do: set(:balance, expr(owner.balance))))

      assert error.message =~ ~r/cannot follow relationships; expose a calculation/
    end

    test "THEN reading the actor is rejected" do
      error = spend_error(quote(do: set(:balance, expr(^actor(:balance)))))

      assert error.message =~ ~r/cannot read the actor/
    end

    test "THEN reading the actor without a pin is rejected" do
      error = spend_error(quote(do: set(:balance, expr(actor(:balance)))))

      assert error.message =~ ~r/cannot read the actor/
    end

    test "THEN an accepted attribute of the action reads like an argument and passes" do
      assert [] ==
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :open do
                       set(:shown_balance, expr(arg(:balance) * 2))
                     end
                   end
                 end
               )
    end

    test "THEN an attribute the action does not accept is rejected as not an argument" do
      assert [%DslError{message: message}] =
               verifier_errors(
                 quote do
                   optimistic_ui do
                     optimistic :open do
                       set(:balance, expr(arg(:id)))
                     end
                   end
                 end
               )

      assert message =~ ~r/:id is not an argument of :open/
    end

    test "THEN a pinned argument the action does not take is rejected" do
      error = spend_error(quote(do: set(:balance, expr(^arg(:price)))))

      assert error.message =~ ~r/:price is not an argument of :spend/
    end
  end

  describe "GIVEN the optimistic UI rules verifier WHEN an opt-out is declared" do
    defp not_optimistic_errors(lines) do
      verifier_errors(
        quote do
          optimistic_ui do
            (unquote_splicing(lines))
          end
        end
      )
    end

    test "THEN every listed reason passes on create, update and generic actions" do
      for {reason, action} <-
            Enum.zip(
              AshBackendDrivenOptimisticUi.NotOptimistic.reasons(),
              Stream.cycle([:open, :spend, :announce])
            ) do
        assert [] ==
                 not_optimistic_errors([
                   quote(do: not_optimistic(unquote(action), because: unquote(reason)))
                 ])
      end
    end

    test "THEN the reasons are exactly the documented five" do
      assert AshBackendDrivenOptimisticUi.NotOptimistic.reasons() ==
               [
                 :ai_result,
                 :server_decides,
                 :background,
                 :admin,
                 :not_yet
               ]
    end

    test "THEN an action the resource does not have is rejected" do
      assert [%DslError{path: path, message: message}] =
               not_optimistic_errors([quote(do: not_optimistic(:ghost, because: :admin))])

      assert path == [:optimistic_ui, :not_optimistic, :ghost]
      assert message =~ "no action :ghost on this resource"
    end

    test "THEN a read action is rejected" do
      assert [%DslError{message: message}] =
               not_optimistic_errors([quote(do: not_optimistic(:read, because: :admin))])

      assert message =~ ~r/:read is a read action/
    end

    test "THEN a reason outside the list is rejected" do
      assert_raise DslError, ~r/:ai_result/, fn ->
        not_optimistic_errors([quote(do: not_optimistic(:open, because: :lazy))])
      end
    end

    test "THEN the same action named twice is rejected" do
      assert [%DslError{message: message}] =
               not_optimistic_errors([
                 quote(do: not_optimistic(:open, because: :admin)),
                 quote(do: not_optimistic(:open, because: :not_yet))
               ])

      assert message =~ ":open is named twice"
    end

    test "THEN an action that is both optimistic and not_optimistic is rejected" do
      assert [%DslError{message: message}] =
               not_optimistic_errors([
                 quote(do: optimistic(:open)),
                 quote(do: not_optimistic(:open, because: :admin))
               ])

      assert message =~ ":open has both `optimistic` and `not_optimistic`"
    end
  end
end
