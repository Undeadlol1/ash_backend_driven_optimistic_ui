defmodule AshBackendDrivenOptimisticUi.CompilerTest do
  use ExUnit.Case, async: true

  import Ash.Expr
  import AshBackendDrivenOptimisticUi.TestHelpers, only: [input: 1, record: 1]

  alias Ash.Query.Call
  alias AshBackendDrivenOptimisticUi.Compiler

  describe "GIVEN the optimistic UI compiler WHEN an arithmetic or comparison expression is compiled" do
    test "THEN each operator maps to the same-named json logic operator" do
      assert Compiler.compile(expr(a + 1)) == {:ok, %{"+" => [record(:a), 1]}}
      assert Compiler.compile(expr(a - 1)) == {:ok, %{"-" => [record(:a), 1]}}
      assert Compiler.compile(expr(a * 2)) == {:ok, %{"*" => [record(:a), 2]}}
      assert Compiler.compile(expr(a / 2)) == {:ok, %{"/" => [record(:a), 2]}}
      assert Compiler.compile(expr(a == 1)) == {:ok, %{"==" => [record(:a), 1]}}
      assert Compiler.compile(expr(a != 1)) == {:ok, %{"!=" => [record(:a), 1]}}
      assert Compiler.compile(expr(a < 1)) == {:ok, %{"<" => [record(:a), 1]}}
      assert Compiler.compile(expr(a > 1)) == {:ok, %{">" => [record(:a), 1]}}
      assert Compiler.compile(expr(a <= 1)) == {:ok, %{"<=" => [record(:a), 1]}}
      assert Compiler.compile(expr(a >= 1)) == {:ok, %{">=" => [record(:a), 1]}}
    end

    test "THEN unary minus keeps its single operand" do
      assert Compiler.compile(expr(-a)) == {:ok, %{"-" => [record(:a)]}}
    end

    test "THEN string concatenation becomes cat" do
      assert Compiler.compile(expr(a <> "!")) == {:ok, %{"cat" => [record(:a), "!"]}}
    end

    test "THEN nested concatenation flattens into one cat list" do
      assert Compiler.compile(expr(a <> "-" <> b <> "!")) ==
               {:ok, %{"cat" => [record(:a), "-", record(:b), "!"]}}

      assert Compiler.compile(expr((a <> "-") <> b <> "!")) ==
               {:ok, %{"cat" => [record(:a), "-", record(:b), "!"]}}
    end

    test "THEN an event reads the pushed event's payload" do
      assert Compiler.compile(expr(event(:amount))) == {:ok, %{"var" => "event.amount"}}

      assert Compiler.compile(expr(a + event(:amount))) ==
               {:ok, %{"+" => [record(:a), %{"var" => "event.amount"}]}}
    end

    test "THEN membership becomes in with the list compiled" do
      assert Compiler.compile(expr(a in [1, 2])) == {:ok, %{"in" => [record(:a), [1, 2]]}}
    end
  end

  describe "GIVEN the optimistic UI compiler WHEN a boolean expression is compiled" do
    test "THEN an and chain flattens into one list" do
      assert Compiler.compile(expr(a > 1 and b < 2 and c == 3)) ==
               {:ok,
                %{
                  "and" => [
                    %{">" => [record(:a), 1]},
                    %{"<" => [record(:b), 2]},
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
               {:ok, %{"if" => [%{">" => [record(:a), 1]}, "big", "small"]}}
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
