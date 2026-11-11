defmodule ElixirAvro.E2ETest do
  use ExUnit.Case

  defmodule AvroraClient do
    use Avrora.Client,
      schemas_path: Path.join(__DIR__, "e2e/avro_schemas")
  end

  setup_all do
    {:ok, _} = AvroraClient.start_link()

    schemas_path = Path.join(__DIR__, "e2e/avro_schemas")
    target_path = Path.join(__DIR__, "e2e/generated")
    File.rm_rf!(target_path)

    args = %{target_path: target_path, schemas_path: schemas_path, prefix: "MyApp.AvroGenerated"}
    ElixirAvro.Codegen.run(args)

    generated_path = Path.join(target_path, "my_app/avro_generated/io/confluent")
    files = generated_path |> File.ls!() |> Enum.sort()

    assert files == [
             "all_types_example.ex",
             "defaults_enum.ex",
             "defaults_example.ex",
             "example_enum.ex",
             "example_record.ex",
             "nested_enum.ex",
             "nested_record.ex"
           ]

    Enum.map(files, &Code.compile_file(Path.join(generated_path, &1)))

    Code.compile_file("test/elixir_avro/e2e/fixtures.exs")
  end

  test "implements jason" do
    to_avro = ElixirAvro.E2E.Fixtures

    avro_struct = to_avro.all_types_example(:struct)

    assert {:ok, _} = Jason.encode(avro_struct)
  end

  test "encode and decode" do
    # We need to define a variable to reference modules just compiled
    # avoiding a warning about undefined module
    to_avro = ElixirAvro.E2E.Fixtures

    assert {:ok, avro_map} = to_avro.all_types_example(:map)

    assert {:ok, encoded} =
             AvroraClient.encode_plain(avro_map,
               schema_name: "AllTypesExample"
             )

    assert {:ok,
            %{
              "array_field" => ["item1", "item2", "item3"],
              "boolean_field" => true,
              "bytes_field" => <<1, 2, 3>>,
              "date_field" => 19_754,
              "double_field" => 2.71828,
              "enum_field" => "SYMBOL1",
              "float_field" => float_value,
              "int_field" => 42,
              "long_field" => 1_234_567_890,
              "map_field" => %{"key1" => 1, "key2" => 2, "key3" => 3},
              "null_field" => nil,
              "record_field" => %{
                "nested_enum" => "NESTED_SYMBOL2",
                "nested_int" => 123,
                "nested_record" => %{
                  "nested_enum" => "NESTED_SYMBOL1",
                  "nested_string" => "Nested Record String"
                },
                "nested_string" => "Nested String",
                "union_with_refs_field" => "SYMBOL1"
              },
              "string_field" => "Hello, Avro!",
              "timestamp_millis_field" => 1_704_070_923_000,
              "union_field" => 42,
              "uuid_field" => "34de4cfa-ced0-4b4a-bf2d-bd2e9283a40a"
            } = decoded} = AvroraClient.decode_plain(encoded, schema_name: "AllTypesExample")

    # Floats have rounding problems right now. I don't how to fix it in avrora.
    rounded_float = 3.14
    assert rounded_float == Float.round(float_value, 2)
    decoded = Map.put(decoded, "float_field", rounded_float)

    assert {:ok, to_avro.all_types_example(:struct)} ==
             to_avro.all_types_example(:from_avro, decoded)
  end

  test "encode and decode, array as union value" do
    # We need to define a variable to reference modules just compiled
    to_avro = ElixirAvro.E2E.Fixtures

    assert {:ok, avro_map} = to_avro.all_types_example2(:map)

    assert {:ok, encoded} =
             AvroraClient.encode_plain(avro_map,
               schema_name: "AllTypesExample"
             )

    assert {:ok,
            %{
              "array_field" => ["item1", "item2", "item3"],
              "boolean_field" => true,
              "bytes_field" => <<1, 2, 3>>,
              "date_field" => 19_754,
              "double_field" => 2.71828,
              "enum_field" => "SYMBOL1",
              "float_field" => _,
              "int_field" => 42,
              "long_field" => 1_234_567_890,
              "map_field" => %{"key1" => 1, "key2" => 2, "key3" => 3},
              "null_field" => nil,
              "record_field" => %{
                "nested_enum" => "NESTED_SYMBOL2",
                "nested_int" => 123,
                "nested_record" => %{
                  "nested_enum" => "NESTED_SYMBOL1",
                  "nested_string" => "Nested Record String"
                },
                "nested_string" => "Nested String",
                "union_with_refs_field" => "NESTED_SYMBOL1"
              },
              "string_field" => "Hello, Avro!",
              "timestamp_millis_field" => 1_704_070_923_000,
              "union_field" => [124, 1_000_001],
              "uuid_field" => "34de4cfa-ced0-4b4a-bf2d-bd2e9283a40a"
            }} = AvroraClient.decode_plain(encoded, schema_name: "AllTypesExample")
  end

  describe "defaults" do
    @required %{"required_string" => "required", "required_int" => 1}

    test "from_avro gives the defaults for the absent keys" do
      fixtures = ElixirAvro.E2E.Fixtures

      assert {:ok, fixtures.defaults_example(:defaults)} ==
               fixtures.defaults_example(:from_avro, @required)
    end

    test "from_avro gives the present values over the defaults" do
      fixtures = ElixirAvro.E2E.Fixtures

      assert {:ok, avro_map} = fixtures.defaults_example(:map)

      assert {:ok, fixtures.defaults_example(:struct)} ==
               fixtures.defaults_example(:from_avro, avro_map)

      assert {:ok, %{string_or_null_field: nil, int_field: 7}} =
               fixtures.defaults_example(
                 :from_avro,
                 Map.put(@required, "string_or_null_field", nil)
               )
    end

    test "from_avro names only the absent required keys" do
      fixtures = ElixirAvro.E2E.Fixtures

      assert {:error, "Missing keys: required_int, required_string"} ==
               fixtures.defaults_example(:from_avro, %{})

      assert {:error, "Missing keys: required_int"} ==
               fixtures.defaults_example(:from_avro, %{
                 "required_string" => "required",
                 "boolean_field" => false
               })
    end

    test "to_avro emits every field and from_avro reads it back, also through Avro" do
      fixtures = ElixirAvro.E2E.Fixtures

      assert {:ok, avro_map} = fixtures.defaults_example(:map)
      assert map_size(avro_map) == 17

      assert {:ok, encoded} = AvroraClient.encode_plain(avro_map, schema_name: "DefaultsExample")
      assert {:ok, decoded} = AvroraClient.decode_plain(encoded, schema_name: "DefaultsExample")

      assert {:ok, fixtures.defaults_example(:struct)} ==
               fixtures.defaults_example(:from_avro, decoded)
    end
  end
end

defmodule ElixirAvro.AvroType.TestLogical do
  @moduledoc false

  @behaviour ElixirAvro.AvroType.LogicalType

  @type t :: %__MODULE__{
          value: String.t()
        }

  defstruct [:value]

  @impl ElixirAvro.AvroType.LogicalType
  def decode(value), do: {:ok, %__MODULE__{value: value}}

  @impl ElixirAvro.AvroType.LogicalType
  def encode(%__MODULE__{value: value}), do: {:ok, value}
end
