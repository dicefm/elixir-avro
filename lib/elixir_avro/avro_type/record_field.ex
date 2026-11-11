defmodule ElixirAvro.AvroType.RecordField do
  @moduledoc """
  A field of an Avro record.

  `default` is `:undefined` for a field without a default. Otherwise it holds the schema default
  in the shape the generated `from_avro/1` receives on the wire, the shape a JSON-decoded payload
  has for the field's type:

    * `null` is `nil`; booleans, numbers, strings and bytes stay as they are;
    * an enum or a fixed is its string;
    * an array is a list and a map is a map with string keys, their items converted the same way;
    * a union holds a value of its first branch, which is the branch the Avro specification
      requires a union default to match.

  A logical type keeps its underlying primitive value: a `date` default of `0` stays `0`, and the
  decoder turns it into `~D[1970-01-01]` like any payload value.
  """

  alias ElixirAvro.AvroType
  alias ElixirAvro.AvroType.Array
  alias ElixirAvro.AvroType.Fixed
  alias ElixirAvro.AvroType.Primitive
  alias ElixirAvro.AvroType.Union

  @type t :: %__MODULE__{
          name: String.t(),
          type: AvroType.t(),
          doc: String.t(),
          default: :undefined | term(),
          order: :ascending | :descending | :ignore,
          aliases: [String.t()]
        }

  defstruct [
    :name,
    :type,
    :doc,
    :default,
    :order,
    :aliases
  ]

  @doc """
  Builds a field from an erlavro record field.

  erlavro has already checked the default against the field's type and hands it over unwrapped:
  `null` as `:null`, a map as a list of `{key, value}` pairs. The default is stored converted to
  the wire shape described in the module doc.

  Raises `ArgumentError` naming the field and its type for a default that has no wire shape here:
  a record default, or a non-empty array or map default whose items are unions.
  """
  @spec from_erl(:avro.record_field()) :: t() | no_return()
  def from_erl({_, name, doc, type, default, order, aliases}) do
    field = %__MODULE__{
      name: name,
      type: AvroType.from_erl(type),
      doc: doc,
      default: :undefined,
      order: order,
      aliases: aliases
    }

    %__MODULE__{field | default: wire_default(default, field)}
  end

  @doc """
  Returns whether the field has a default, which lets a payload omit it.
  """
  @spec default?(t()) :: boolean()
  def default?(%__MODULE__{default: default}), do: default != :undefined

  @spec wire_default(term(), t()) :: term() | no_return()
  defp wire_default(:undefined, _), do: :undefined

  defp wire_default(default, %__MODULE__{type: %Union{values: %{0 => first_branch}}} = field) do
    to_wire(default, first_branch, field)
  end

  defp wire_default(default, %__MODULE__{type: type} = field), do: to_wire(default, type, field)

  @spec to_wire(term(), AvroType.t(), t()) :: term() | no_return()
  defp to_wire(:null, %Primitive{name: "null"}, _), do: nil
  defp to_wire(value, %Primitive{}, _), do: value

  defp to_wire(items, %Array{type: type}, field) when is_list(items) do
    for item <- items, do: to_wire(item, type, field)
  end

  defp to_wire(pairs, %AvroType.Map{type: type}, field) when is_list(pairs) do
    Map.new(pairs, fn {key, value} -> {key, to_wire(value, type, field)} end)
  end

  defp to_wire(symbol, %AvroType.Enum{}, _) when is_binary(symbol), do: symbol
  defp to_wire(value, %Fixed{}, _) when is_binary(value), do: value

  # A named type defined in a schema is a reference by the time it reaches a field. erlavro only
  # accepts a string default for an enum or a fixed; a record default is a list of fields.
  defp to_wire(value, reference, _) when is_binary(reference) and is_binary(value), do: value

  defp to_wire(_, _, %__MODULE__{name: name, type: type}) do
    raise ArgumentError,
          "unsupported default for record field #{inspect(name)} of type #{inspect(type)}: " <>
            "record defaults and union items in a non-empty array or map default " <>
            "cannot be generated"
  end
end
