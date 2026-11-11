defmodule ElixirAvro.AvroType.RecordFieldTest do
  use ExUnit.Case, async: true

  alias ElixirAvro.AvroType.RecordField
  alias ElixirAvro.Schema.Resolver

  describe "from_erl/1 default" do
    test "is :undefined when the field has none" do
      field = parse_field(~s("int"))

      assert field.default == :undefined
      refute RecordField.default?(field)
    end

    test "null is nil" do
      field = parse_field(~s("null"), "null")

      assert field.default == nil
      assert RecordField.default?(field)
    end

    test "boolean" do
      assert parse_field(~s("boolean"), "true").default == true
      assert parse_field(~s("boolean"), "false").default == false
    end

    test "int and long" do
      assert parse_field(~s("int"), "-7").default == -7
      assert parse_field(~s("long"), "9000000000").default == 9_000_000_000
    end

    test "float and double, also when written as an integer" do
      assert parse_field(~s("float"), "1.5").default == 1.5
      assert parse_field(~s("double"), "2.25").default == 2.25
      assert parse_field(~s("double"), "2").default == 2.0
    end

    test "string" do
      assert parse_field(~s("string"), ~s("unknown")).default == "unknown"
    end

    test "logical type keeps the underlying primitive value" do
      field = parse_field(~s({"type": "int", "logicalType": "date"}), "0")

      assert field.default == 0
    end

    test "inline enum is its symbol" do
      field =
        parse_field(
          ~s({"type": "enum", "name": "Hand", "symbols": ["LEFT", "RIGHT"]}),
          ~s("RIGHT")
        )

      assert field.type == "test.Hand"
      assert field.default == "RIGHT"
    end

    test "union with a null first branch is nil" do
      assert parse_field(~s(["null", "string"]), "null").default == nil
    end

    test "union holds a value of its first branch" do
      assert parse_field(~s(["string", "null"]), ~s("none")).default == "none"
      assert parse_field(~s([{"type": "array", "items": "int"}, "null"]), "[]").default == []
      assert parse_field(~s([{"type": "map", "values": "int"}, "null"]), "{}").default == %{}

      field =
        parse_field(
          ~s([{"type": "enum", "name": "Hand", "symbols": ["LEFT", "RIGHT"]}, "null"]),
          ~s("LEFT")
        )

      assert field.default == "LEFT"
    end

    test "empty array is an empty list" do
      assert parse_field(~s({"type": "array", "items": "string"}), "[]").default == []
    end

    test "empty map is an empty map, not a list" do
      assert parse_field(~s({"type": "map", "values": "int"}), "{}").default == %{}
    end

    test "array and map items are converted by their own type" do
      assert parse_field(~s({"type": "array", "items": "int"}), "[1, 2]").default == [1, 2]
      assert parse_field(~s({"type": "array", "items": "null"}), "[null]").default == [nil]

      field =
        parse_field(
          ~s({"type": "map", "values": {"type": "map", "values": {"type": "array", "items": "null"}}}),
          ~s({"a": {"b": [null]}, "c": {}})
        )

      assert field.default == %{"a" => %{"b" => [nil]}, "c" => %{}}
    end

    test "union items in an empty array are fine" do
      field = parse_field(~s({"type": "array", "items": ["null", "string"]}), "[]")

      assert field.default == []
    end

    test "union items in a non-empty array raise naming the field and type" do
      message =
        ~r/unsupported default for record field "field" of type %ElixirAvro.AvroType.Array\{/

      assert_raise ArgumentError, message, fn ->
        parse_field(~s({"type": "array", "items": ["null", "string"]}), ~s([{"string": "a"}]))
      end
    end

    test "record raises naming the field and type" do
      type = ~s({"type": "record", "name": "Inner", "fields": [{"name": "x", "type": "int"}]})

      assert_raise ArgumentError,
                   ~r/unsupported default for record field "field" of type "test.Inner"/,
                   fn -> parse_field(type, ~s({"x": 1})) end
    end

    test "union with a record first branch raises" do
      type = ~s([{"type": "record", "name": "Inner", "fields": []}, "null"])

      assert_raise ArgumentError, ~r/unsupported default for record field "field"/, fn ->
        parse_field(type, "{}")
      end
    end
  end

  # Runs the schema through the resolver, as the code generator does, and parses the one field.
  defp parse_field(type_json, default_json \\ nil) do
    default = if default_json, do: ~s(, "default": #{default_json}), else: ""

    schema = """
    {"type": "record", "name": "Holder", "namespace": "test",
     "fields": [{"name": "field", "type": #{type_json}#{default}}]}
    """

    [schema]
    |> Resolver.resolve_types()
    |> Enum.find(&match?({:avro_record_type, "Holder", _, _, _, _, _, _}, &1))
    |> elem(5)
    |> hd()
    |> RecordField.from_erl()
  end
end
