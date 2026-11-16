defmodule AshBackendDrivenOptimisticUi.JsonLogicTest do
  use ExUnit.Case, async: true

  alias AshBackendDrivenOptimisticUi.JsonLogic

  @data %{
    "record" => %{"xp" => 10, "name" => "Ann", "tags" => ["a", "b"], "nothing" => nil},
    "input" => %{"amount" => 4},
    "ctx" => %{"copy" => %{"title" => "Hi"}}
  }

  describe "GIVEN the JSON Logic evaluator" do
    test "WHEN a dotted path is read from the record THEN it returns the value there" do
      assert JsonLogic.run(%{"var" => "record.xp"}, @data) == 10
    end

    test "WHEN a deeply nested path is read from ctx THEN it returns the value there" do
      assert JsonLogic.run(%{"var" => "ctx.copy.title"}, @data) == "Hi"
    end

    test "WHEN a missing path is read THEN it returns nil" do
      assert JsonLogic.run(%{"var" => "record.missing.deeper"}, @data) == nil
    end

    test "WHEN has asks for a key whose value is null THEN it is true" do
      assert JsonLogic.run(%{"has" => "record.nothing"}, @data) == true
    end

    test "WHEN has asks for a key with a value THEN it is true" do
      assert JsonLogic.run(%{"has" => "input.amount"}, @data) == true
    end

    test "WHEN has asks for a key that is not there THEN it is false" do
      assert JsonLogic.run(%{"has" => "input.missing"}, @data) == false
    end

    test "WHEN has asks below a value that is not a map THEN it is false" do
      assert JsonLogic.run(%{"has" => "record.xp.deeper"}, @data) == false
    end

    test "WHEN a sum of a record value, an input value and 1 is computed THEN it adds them up" do
      assert JsonLogic.run(
               %{"+" => [%{"var" => "record.xp"}, %{"var" => "input.amount"}, 1]},
               @data
             ) == 15
    end

    test "WHEN 3 is subtracted from a record value THEN it returns the difference" do
      assert JsonLogic.run(%{"-" => [%{"var" => "record.xp"}, 3]}, @data) == 7
    end

    test "WHEN an input value is negated THEN it returns the opposite sign" do
      assert JsonLogic.run(%{"-" => [%{"var" => "input.amount"}]}, @data) == -4
    end

    test "WHEN an input value is multiplied by 2.5 THEN it returns the product" do
      assert JsonLogic.run(%{"*" => [%{"var" => "input.amount"}, 2.5]}, @data) == 10.0
    end

    test "WHEN a record value is divided by 4 THEN it returns the quotient" do
      assert JsonLogic.run(%{"/" => [%{"var" => "record.xp"}, 4]}, @data) == 2.5
    end

    test "WHEN an integer is compared with an equal float using equality THEN they are equal" do
      assert JsonLogic.run(%{"==" => [%{"var" => "record.xp"}, 10.0]}, @data) == true
    end

    test "WHEN a name is compared with another name using not equal THEN they differ" do
      assert JsonLogic.run(%{"!=" => [%{"var" => "record.name"}, "Bob"]}, @data) == true
    end

    test "WHEN 1 is compared with 2 using less than THEN it is true" do
      assert JsonLogic.run(%{"<" => [1, 2]}, @data) == true
    end

    test "WHEN 1 is compared with 2 using greater than THEN it is false" do
      assert JsonLogic.run(%{">" => [1, 2]}, @data) == false
    end

    test "WHEN 2 is compared with 2 using less or equal THEN it is true" do
      assert JsonLogic.run(%{"<=" => [2, 2]}, @data) == true
    end

    test "WHEN 1 is compared with 2 using greater or equal THEN it is false" do
      assert JsonLogic.run(%{">=" => [1, 2]}, @data) == false
    end

    test "WHEN and holds true, 0 and a text THEN it returns the first falsy operand, which is 0" do
      assert JsonLogic.run(%{"and" => [true, 0, "x"]}, @data) == 0
    end

    test "WHEN and holds only truthy operands THEN it returns the last operand" do
      assert JsonLogic.run(%{"and" => [true, "x"]}, @data) == "x"
    end

    test "WHEN or holds nil, empty text and two texts THEN it returns the first truthy operand" do
      assert JsonLogic.run(%{"or" => [nil, "", "x", "y"]}, @data) == "x"
    end

    test "WHEN or holds only falsy operands THEN it returns the last operand" do
      assert JsonLogic.run(%{"or" => [false, nil]}, @data) == nil
    end

    test "WHEN not is applied to a nil record value THEN it returns true" do
      assert JsonLogic.run(%{"!" => [%{"var" => "record.nothing"}]}, @data) == true
    end

    test "WHEN if has a true condition THEN it picks the then branch" do
      assert JsonLogic.run(%{"if" => [true, "yes", "no"]}, @data) == "yes"
    end

    test "WHEN if has a nil condition THEN it picks the else branch" do
      assert JsonLogic.run(%{"if" => [%{"var" => "record.nothing"}, "yes", "no"]}, @data) == "no"
    end

    test "WHEN cat joins text, integers and floats THEN it returns one text" do
      assert JsonLogic.run(%{"cat" => ["lv ", 3, " ", 2.0, " ", 2.5]}, @data) == "lv 3 2 2.5"
    end

    test "WHEN in looks for a text inside a list THEN it finds the member" do
      assert JsonLogic.run(%{"in" => ["a", %{"var" => "record.tags"}]}, @data) == true
    end

    test "WHEN in looks for a text inside a longer text THEN it finds the substring" do
      assert JsonLogic.run(%{"in" => ["nn", %{"var" => "record.name"}]}, @data) == true
    end

    test "WHEN abs is applied to -3 THEN it returns 3" do
      assert JsonLogic.run(%{"abs" => [-3]}, @data) == 3
    end

    test "WHEN round is applied to 2.5 THEN it returns 3" do
      assert JsonLogic.run(%{"round" => [2.5]}, @data) == 3
    end

    test "WHEN round is applied to 2.345 with 2 places THEN it returns 2.35" do
      assert JsonLogic.run(%{"round" => [2.345, 2]}, @data) == 2.35
    end

    test "WHEN now is run THEN it returns the current UTC time as ISO 8601 text" do
      before = DateTime.utc_now()

      {:ok, shown, 0} = DateTime.from_iso8601(JsonLogic.run(%{"now" => []}, @data))

      assert DateTime.compare(shown, before) != :lt
    end

    test "WHEN to_string is applied to 5.0 THEN it returns the text 5" do
      assert JsonLogic.run(%{"to_string" => [5.0]}, @data) == "5"
    end

    test "WHEN a numeric text 10 is added to 5 THEN it is parsed and added" do
      assert JsonLogic.run(%{"+" => ["10", 5]}, @data) == 15
    end

    test "WHEN a decimal text 10.5 is added to 1 THEN it is parsed and added" do
      assert JsonLogic.run(%{"+" => ["10.5", 1]}, @data) == 11.5
    end

    test "WHEN a decimal text 2.5 is multiplied by 2 THEN it is parsed and multiplied" do
      assert JsonLogic.run(%{"*" => ["2.5", 2]}, @data) == 5.0
    end

    test "WHEN a numeric text 4 is negated THEN it is parsed and negated" do
      assert JsonLogic.run(%{"-" => ["4"]}, @data) == -4
    end

    test "WHEN two numeric texts 9 and 2 are divided THEN both are parsed and divided" do
      assert JsonLogic.run(%{"/" => ["9", "2"]}, @data) == 4.5
    end

    test "WHEN a numeric text 9 is compared with 10 using less than THEN it is parsed first" do
      assert JsonLogic.run(%{"<" => ["9", 10]}, @data) == true
    end

    test "WHEN a numeric text 3 is compared with 2 using greater or equal THEN it is parsed first" do
      assert JsonLogic.run(%{">=" => ["3", 2]}, @data) == true
    end

    test "WHEN two texts 10 and 9 are compared using less or equal THEN they compare as numbers" do
      assert JsonLogic.run(%{"<=" => ["10", "9"]}, @data) == false
    end

    test "WHEN a numeric text 10 is compared with the number 10 THEN they are equal" do
      assert JsonLogic.run(%{"==" => ["10", 10]}, @data) == true
    end

    test "WHEN a decimal text 10.5 is compared with the float 10.5 THEN they are equal" do
      assert JsonLogic.run(%{"==" => ["10.5", 10.5]}, @data) == true
    end

    test "WHEN two texts 10 and 10.0 are compared THEN they differ as text" do
      assert JsonLogic.run(%{"==" => ["10", "10.0"]}, @data) == false
    end

    test "WHEN a text that is not a number is compared with 10 THEN they differ" do
      assert JsonLogic.run(%{"==" => ["abc", 10]}, @data) == false
    end

    test "WHEN a numeric text 10 is compared with the number 10 using not equal THEN it is false" do
      assert JsonLogic.run(%{"!=" => ["10", 10]}, @data) == false
    end

    test "WHEN abs is applied to the text -3 THEN it returns 3" do
      assert JsonLogic.run(%{"abs" => ["-3"]}, @data) == 3
    end

    test "WHEN round is applied to the text 2.5 THEN it returns 3" do
      assert JsonLogic.run(%{"round" => ["2.5"]}, @data) == 3
    end

    test "WHEN cat joins 3.0 THEN it shows no fraction" do
      assert JsonLogic.run(%{"cat" => [3.0]}, @data) == "3"
    end

    test "WHEN cat joins 0.5 THEN it shows the fraction" do
      assert JsonLogic.run(%{"cat" => [0.5]}, @data) == "0.5"
    end

    test "WHEN cat joins text, nil and text THEN nil adds nothing" do
      assert JsonLogic.run(%{"cat" => ["a", nil, "b"]}, @data) == "ab"
    end

    test "WHEN cat joins true and false THEN it joins them as the texts true and false" do
      assert JsonLogic.run(%{"cat" => [true, false]}, @data) == "truefalse"
    end

    test "WHEN cat joins two negative floats THEN it shows their signs" do
      assert JsonLogic.run(%{"cat" => [-2.0, -1.5]}, @data) == "-2-1.5"
    end

    test "WHEN to_string is applied to 1.5 THEN it returns the text 1.5" do
      assert JsonLogic.run(%{"to_string" => [1.5]}, @data) == "1.5"
    end

    test "WHEN a number literal is run THEN it returns the number" do
      assert JsonLogic.run(7, @data) == 7
    end

    test "WHEN a text literal is run THEN it returns the text" do
      assert JsonLogic.run("text", @data) == "text"
    end

    test "WHEN nil is run THEN it returns nil" do
      assert JsonLogic.run(nil, @data) == nil
    end

    test "WHEN a list literal is run THEN each element is evaluated" do
      assert JsonLogic.run([1, %{"var" => "record.xp"}], @data) == [1, 10]
    end

    test "WHEN arithmetic gets a value that is not a number THEN it raises like the client does" do
      assert_raise ArgumentError, ~r/Not a number/, fn ->
        JsonLogic.run(%{"+" => ["abc", 1]}, @data)
      end

      assert_raise ArgumentError, ~r/Not a number/, fn ->
        JsonLogic.run(%{"+" => [nil, 1]}, @data)
      end

      assert_raise ArgumentError, ~r/Not a number/, fn ->
        JsonLogic.run(%{"<" => ["a", "b"]}, @data)
      end
    end

    test "WHEN the operator is unknown THEN it raises naming the operator" do
      error = assert_raise ArgumentError, fn -> JsonLogic.run(%{"merge" => [1, 2]}, @data) end

      assert error.message =~ "merge"
    end

    test "WHEN a map holds more than one operator THEN it raises" do
      assert_raise ArgumentError, fn -> JsonLogic.run(%{"+" => [1], "-" => [1]}, @data) end
    end

    test "WHEN truthy? checks falsy and truthy values THEN only zero, empty text, empty list, nil and false are falsy" do
      assert Enum.map([0, "", [], nil, false, 1, "a", [0]], &JsonLogic.truthy?/1) ==
               [false, false, false, false, false, true, true, true]
    end
  end

  @fixtures ["json_logic_official_tests.json", "json_logic_extras_tests.json"]

  describe "GIVEN the official JSON Logic suite and our extras" do
    test "WHEN every case is evaluated THEN each one gives its expected result" do
      failures =
        for file <- @fixtures,
            case_ <- file |> fixture_cases() |> Enum.reject(&is_binary/1),
            not passes?(case_),
            do: {file, case_}

      assert failures == [], "failing cases:\n#{Enum.map_join(failures, "\n", &inspect/1)}"
    end
  end

  defp fixture_cases(file) do
    "test/fixtures"
    |> Path.join(file)
    |> File.read!()
    |> Jason.decode!()
  end

  defp passes?([rule, data, expected]) do
    JsonLogic.run(rule, data) == expected
  rescue
    _error -> false
  end
end
