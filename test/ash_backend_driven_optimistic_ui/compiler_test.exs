defmodule AshBackendDrivenOptimisticUi.CompilerTest do
  use ExUnit.Case, async: true

  import Ash.Expr
  import AshBackendDrivenOptimisticUi.TestHelpers, only: [input: 1, record: 1]

  alias Ash.Query.Call
  alias AshBackendDrivenOptimisticUi.Compiler
  alias AshBackendDrivenOptimisticUi.TestSupport.ComparisonResource

  defp attr_ref(name), do: %Ash.Query.Ref{attribute: name, relationship_path: []}
  defp present(name), do: %{"!=" => [record(name), nil]}

  describe "GIVEN the optimistic UI compiler WHEN an arithmetic or comparison expression is compiled" do
    test "THEN each operator maps to the same-named json logic operator" do
      assert Compiler.compile(expr(a + 1)) == {:ok, %{"+" => [record(:a), 1]}}
      assert Compiler.compile(expr(a - 1)) == {:ok, %{"-" => [record(:a), 1]}}
      assert Compiler.compile(expr(a * 2)) == {:ok, %{"*" => [record(:a), 2]}}
      assert Compiler.compile(expr(a / 2)) == {:ok, %{"/" => [record(:a), 2]}}
      assert Compiler.compile(expr(a == 1)) == {:ok, %{"==" => [record(:a), 1]}}
      assert Compiler.compile(expr(a != 1)) == {:ok, %{"and" => [present(:a), %{"!=" => [record(:a), 1]}]}}
      assert Compiler.compile(expr(a < 1)) == {:ok, %{"<" => [%{"+" => [record(:a)]}, 1]}}
      assert Compiler.compile(expr(a > 1)) == {:ok, %{">" => [%{"+" => [record(:a)]}, 1]}}
      assert Compiler.compile(expr(a <= 1)) == {:ok, %{"<=" => [%{"+" => [record(:a)]}, 1]}}
      assert Compiler.compile(expr(a >= 1)) == {:ok, %{">=" => [%{"+" => [record(:a)]}, 1]}}
    end

    test "THEN unary minus keeps its single operand" do
      assert Compiler.compile(expr(-a)) == {:ok, %{"-" => [record(:a)]}}
    end

    test "THEN string concatenation becomes cat with each non-literal operand as text" do
      assert Compiler.compile(expr(a <> "!")) ==
               {:ok, %{"cat" => [%{"to_string" => [record(:a)]}, "!"]}}
    end

    test "THEN a compared operand that is not a number literal is cast with unary plus" do
      assert Compiler.compile(expr(a >= arg(:b))) ==
               {:ok, %{">=" => [%{"+" => [record(:a)]}, %{"+" => [input(:b)]}]}}

      assert Compiler.compile(expr(1 < a)) == {:ok, %{"<" => [1, %{"+" => [record(:a)]}]}}
    end

    test "THEN a comparison with a text literal is not cast" do
      assert Compiler.compile(expr(a < "m")) == {:ok, %{"<" => [record(:a), "m"]}}
      assert Compiler.compile(expr("m" >= a)) == {:ok, %{">=" => ["m", record(:a)]}}
    end

    test "THEN a comparison with a date or time literal compares its ISO 8601 text" do
      assert Compiler.compile(expr(a < ^~D[2000-01-01])) == {:ok, %{"<" => [record(:a), "2000-01-01"]}}
      assert Compiler.compile(expr(a < ^~T[10:30:00])) == {:ok, %{"<" => [record(:a), "10:30:00"]}}
      assert Compiler.compile(expr(a < ^~N[2000-01-01 10:30:00])) == {:ok, %{"<" => [record(:a), "2000-01-01T10:30:00"]}}

      assert Compiler.compile(expr(a < ^~U[2000-01-01 10:30:00Z])) ==
               {:ok, %{"<" => [record(:a), "2000-01-01T10:30:00Z"]}}
    end

    test "THEN attributes and arguments that travel as text are not cast when the resource is given" do
      opts = [resource: ComparisonResource, action: :born_before_cutoff]

      assert Compiler.compile(expr(name < name), opts) == {:ok, %{"<" => [record(:name), record(:name)]}}
      assert Compiler.compile(expr(born_on < arg(:cutoff)), opts) == {:ok, %{"<" => [record(:born_on), input(:cutoff)]}}
      assert Compiler.compile(expr(arg(:cutoff) >= 1), opts) == {:ok, %{">=" => [input(:cutoff), "1"]}}
    end

    test "THEN number and decimal attributes keep the cast when the resource is given" do
      opts = [resource: ComparisonResource, action: :born_before_cutoff]

      assert Compiler.compile(expr(score < amount), opts) ==
               {:ok, %{"<" => [%{"+" => [record(:score)]}, %{"+" => [record(:amount)]}]}}
    end

    test "THEN a date-time literal is written in the text form of the attribute it meets" do
      opts = [resource: ComparisonResource, action: :at_since]

      utc_plus_two = %DateTime{
        year: 2020,
        month: 1,
        day: 1,
        hour: 2,
        minute: 0,
        second: 0,
        microsecond: {0, 0},
        time_zone: "Etc/GMT-2",
        zone_abbr: "+02",
        utc_offset: 7200,
        std_offset: 0
      }

      assert Compiler.compile(expr(at >= ^~U[2020-01-01 00:00:00Z]), opts) ==
               {:ok, %{">=" => [record(:at), "2020-01-01T00:00:00.000000Z"]}}

      assert Compiler.compile(expr(at_sec >= ^~U[2020-01-01 00:00:00Z]), opts) ==
               {:ok, %{">=" => [record(:at_sec), "2020-01-01T00:00:00Z"]}}

      assert Compiler.compile(expr(at == ^utc_plus_two), opts) ==
               {:ok, %{"==" => [record(:at), "2020-01-01T00:00:00.000000Z"]}}

      assert Compiler.compile(expr(at_sec < ^~U[2020-01-01 00:00:00.5Z]), opts) ==
               {:error, {:unsupported, ~U[2020-01-01 00:00:00.5Z]}}
    end

    test "THEN date-times whose text forms differ are unsupported, in every comparison" do
      opts = [resource: ComparisonResource, action: :at_since]

      for operator <- [:<, :>, :<=, :>=, :==, :!=] do
        assert {:error, {:unsupported, _}} =
                 Compiler.compile(%Call{name: operator, args: [attr_ref(:at), attr_ref(:at_sec)]}, opts)

        assert {:error, {:unsupported, _}} =
                 Compiler.compile(%Call{name: operator, args: [attr_ref(:at_sec), %Call{name: :now, args: []}]}, opts)
      end

      assert {:ok, _} = Compiler.compile(expr(at < now()), opts)
      assert {:ok, _} = Compiler.compile(expr(at < at), opts)
      assert {:error, {:unsupported, _}} = Compiler.compile(expr(born_on < at), opts)
    end

    test "THEN nested concatenation flattens into one cat list" do
      assert Compiler.compile(expr(a <> "-" <> b <> "!")) ==
               {:ok, %{"cat" => [%{"to_string" => [record(:a)]}, "-", %{"to_string" => [record(:b)]}, "!"]}}

      assert Compiler.compile(expr((a <> "-") <> b <> "!")) ==
               {:ok, %{"cat" => [%{"to_string" => [record(:a)]}, "-", %{"to_string" => [record(:b)]}, "!"]}}
    end

    test "THEN an event reads the pushed event's payload" do
      assert Compiler.compile(expr(event(:amount))) == {:ok, %{"var" => "event.amount"}}

      assert Compiler.compile(expr(a + event(:amount))) ==
               {:ok, %{"+" => [record(:a), %{"var" => "event.amount"}]}}
    end

    test "THEN membership becomes in with the list compiled, after a check that the value is not nil" do
      assert Compiler.compile(expr(a in [1, 2])) ==
               {:ok, %{"and" => [present(:a), %{"in" => [record(:a), [1, 2]]}]}}
    end

    test "THEN == checks both sides for nil only when neither is a literal" do
      assert Compiler.compile(expr(a == b)) ==
               {:ok, %{"and" => [present(:a), present(:b), %{"==" => [record(:a), record(:b)]}]}}

      assert Compiler.compile(expr(a == "x")) == {:ok, %{"==" => [record(:a), "x"]}}
      assert Compiler.compile(expr(a == nil)) == {:ok, %{"==" => [record(:a), nil]}}
    end

    test "THEN != checks only the sides that are not literals" do
      assert Compiler.compile(expr(a != b)) ==
               {:ok, %{"and" => [present(:a), present(:b), %{"!=" => [record(:a), record(:b)]}]}}

      assert Compiler.compile(expr(1 != 2)) == {:ok, %{"!=" => [1, 2]}}
    end
  end

  describe "GIVEN the optimistic UI compiler WHEN a boolean expression is compiled" do
    test "THEN an and chain flattens into one list" do
      assert Compiler.compile(expr(a > 1 and b < 2 and c == 3)) ==
               {:ok,
                %{
                  "and" => [
                    %{">" => [%{"+" => [record(:a)]}, 1]},
                    %{"<" => [%{"+" => [record(:b)]}, 2]},
                    %{"==" => [record(:c), 3]}
                  ]
                }}
    end

    test "THEN an or chain flattens into one list" do
      assert Compiler.compile(expr(a or b or c)) ==
               {:ok, %{"or" => [record(:a), record(:b), record(:c)]}}
    end

    test "THEN an or nested in an and stays its own node" do
      assert Compiler.compile(expr(a and (b or c))) ==
               {:ok, %{"and" => [record(:a), %{"or" => [record(:b), record(:c)]}]}}
    end

    test "THEN not becomes !" do
      assert Compiler.compile(expr(not a)) == {:ok, %{"!" => [record(:a)]}}
    end
  end

  describe "GIVEN the optimistic UI compiler WHEN a function the client can run is called" do
    test "THEN if with do and else keeps both branches" do
      assert Compiler.compile(expr(if a > 1, do: "big", else: "small")) ==
               {:ok, %{"if" => [%{">" => [%{"+" => [record(:a)]}, 1]}, "big", "small"]}}
    end

    test "THEN if with do only falls back to nil" do
      assert Compiler.compile(expr(if a, do: 1)) == {:ok, %{"if" => [record(:a), 1, nil]}}
    end

    test "THEN if with three positional arguments keeps all three" do
      assert Compiler.compile(%Call{name: :if, args: [expr(a), 1, 2]}) ==
               {:ok, %{"if" => [record(:a), 1, 2]}}
    end

    test "THEN is_nil compares with nil" do
      assert Compiler.compile(expr(is_nil(a))) == {:ok, %{"==" => [record(:a), nil]}}
    end

    test "THEN abs, round and to_string become custom operators" do
      assert Compiler.compile(expr(abs(a))) == {:ok, %{"abs" => [record(:a)]}}
      assert Compiler.compile(expr(round(a))) == {:ok, %{"round" => [record(:a)]}}
      assert Compiler.compile(expr(round(a, 2))) == {:ok, %{"round" => [record(:a), 2]}}
      assert Compiler.compile(expr(to_string(a))) == {:ok, %{"to_string" => [record(:a)]}}
    end

    test "THEN now becomes a custom operator with no operands" do
      assert Compiler.compile(expr(now())) == {:ok, %{"now" => []}}
    end
  end

  describe "GIVEN the optimistic UI compiler WHEN a record attribute, an argument or a context value is read" do
    test "THEN an attribute reads from the record" do
      assert Compiler.compile(expr(total_xp)) == {:ok, record(:total_xp)}
    end

    test "THEN an argument written inside expr reads from the input" do
      assert Compiler.compile(expr(arg(:xp_amount))) == {:ok, input(:xp_amount)}
    end

    test "THEN an argument template reads from the input" do
      assert Compiler.compile(arg(:xp_amount)) == {:ok, input(:xp_amount)}
    end

    test "THEN has_arg asks whether the input carries the key, even as null" do
      assert Compiler.compile(expr(has_arg(:consumed_at))) ==
               {:ok, %{"has" => "input.consumed_at"}}
    end

    test "THEN a context template reads from ctx" do
      assert Compiler.compile(expr(^context(:message))) == {:ok, %{"var" => "ctx.message"}}
    end

    test "THEN a context path is dotted" do
      assert Compiler.compile(expr(^context([:copy, :title]))) ==
               {:ok, %{"var" => "ctx.copy.title"}}
    end
  end

  describe "GIVEN the optimistic UI compiler WHEN a plain value is compiled" do
    test "THEN numbers, strings, booleans and nil pass through" do
      assert Compiler.compile(3) == {:ok, 3}
      assert Compiler.compile(1.5) == {:ok, 1.5}
      assert Compiler.compile("text") == {:ok, "text"}
      assert Compiler.compile(true) == {:ok, true}
      assert Compiler.compile(false) == {:ok, false}
      assert Compiler.compile(nil) == {:ok, nil}
    end

    test "THEN atoms become strings" do
      assert Compiler.compile(:gold) == {:ok, "gold"}
    end

    test "THEN decimals become floats" do
      assert Compiler.compile(Decimal.new("2.5")) == {:ok, 2.5}
    end
  end

  describe "GIVEN the optimistic UI compiler WHEN a node the client cannot run is compiled" do
    test "THEN a function the client does not implement is unsupported" do
      today_call = expr(today())

      assert Compiler.compile(expr(a + today())) == {:error, {:unsupported, today_call}}
    end

    test "THEN round with too many arguments is unsupported" do
      round_call = expr(round(a, 2, 3))

      assert Compiler.compile(round_call) == {:error, {:unsupported, round_call}}
    end

    test "THEN a reference through a relationship is unsupported" do
      relationship_ref = expr(owner.balance)

      assert Compiler.compile(relationship_ref) == {:error, {:unsupported, relationship_ref}}
    end

    test "THEN the actor is unsupported" do
      assert Compiler.compile(expr(^actor(:id))) == {:error, {:unsupported, {:_actor, :id}}}
    end

    test "THEN a map, a tuple and a function are unsupported" do
      identity = &Function.identity/1

      assert Compiler.compile(%{a: 1}) == {:error, {:unsupported, %{a: 1}}}
      assert Compiler.compile({:a, :b}) == {:error, {:unsupported, {:a, :b}}}
      assert Compiler.compile(identity) == {:error, {:unsupported, identity}}
    end
  end
end
