defmodule ElixirAvro.Template.Renderer do
  @moduledoc """
  Module responsible for processing field templates.
  """

  alias ElixirAvro.AvroType.RecordField
  alias ElixirAvro.Template
  alias ElixirAvro.Template.Spec

  @excribe_opts %{hanging: 6, width: 80, indent: 0, align: :left}
  @inspect_opts [limit: :infinity, printable_limit: :infinity, charlists: :as_lists]

  @doc """
  Renders the @moduledoc documentation for the given fields.
  """
  @spec module_doc(Template.t()) :: String.t()
  def module_doc(%Template{fields: fields}) do
    Enum.map_join(fields, "\n  ", &doc/1)
  end

  @spec doc(RecordField.t()) :: String.t()
  defp doc(field) do
    "- __#{field.name}__: #{field.doc}"
    |> String.trim()
    |> Kernel.<>(default_doc(field))
    |> Excribe.format(@excribe_opts)
  end

  @spec default_doc(RecordField.t()) :: String.t()
  defp default_doc(field) do
    if RecordField.default?(field) do
      " (default: `#{inspect(field.default, @inspect_opts)}`)"
    else
      ""
    end
  end

  @doc """
  Renders the @expected_keys module attribute: the fields without a default, which a payload must
  have.
  """
  @spec expected_keys(Template.t()) :: String.t()
  def expected_keys(%Template{fields: fields}) do
    required = Enum.reject(fields, &RecordField.default?/1)
    "[#{Enum.map_join(required, ", ", &~s/"#{&1.name}"/)}]"
  end

  @doc """
  Returns whether any field of the record has a default.
  """
  @spec defaults?(Template.t()) :: boolean()
  def defaults?(%Template{fields: fields}), do: Enum.any?(fields, &RecordField.default?/1)

  @doc """
  Renders the @defaults module attribute: the wire value of each field with a default, keyed by
  the field name.
  """
  @spec defaults(Template.t()) :: String.t()
  def defaults(%Template{fields: fields}) do
    pairs =
      fields
      |> Enum.filter(&RecordField.default?/1)
      |> Enum.map_join(", ", &"#{inspect(&1.name)} => #{inspect(&1.default, @inspect_opts)}")

    "%{#{pairs}}"
  end

  @doc """
  Renders the guards of the `from_avro/1` clause that fills in defaults, one `when` per field with
  a default: the clause matches when the `avro` payload lacks any of their keys.

  Separate guards rather than one `and` chain keep the clause readable, and within credo's
  cyclomatic complexity limit, however many fields have a default.
  """
  @spec default_key_missing_guards(Template.t()) :: String.t()
  def default_key_missing_guards(%Template{fields: fields}) do
    fields
    |> Enum.filter(&RecordField.default?/1)
    |> Enum.map_join(" when ", &~s/not is_map_key(avro, "#{&1.name}")/)
  end

  @doc """
  Renders the @values for enum types.
  """
  @spec values(Template.t()) :: String.t()
  def values(%Template{symbols: symbols}) do
    Enum.map_join(symbols, ", ", &~s/"#{&1}"/)
  end

  @doc """
  Renders the @size for fixed types.
  """
  @spec size(Template.t()) :: String.t()
  def size(%Template{size: size}) do
    size
  end

  @doc """
  Renders the typestruct fields with their specs.
  """
  @spec typedstruct_fields(Template.t()) :: String.t()
  def typedstruct_fields(%Template{prefix: prefix, fields: fields}) do
    Enum.map_join(fields, "\n", &typedstruct_field(&1, prefix))
  end

  @spec typedstruct_field(RecordField.t(), String.t()) :: String.t()
  defp typedstruct_field(%RecordField{name: name, type: type}, prefix) do
    "field :#{name}, #{Spec.to_typedstruct_spec!(type, prefix)}, enforce: #{Spec.enforce?(type)}"
  end

  @spec fields_for_to_avro(Template.t()) :: String.t()
  def fields_for_to_avro(%Template{fields: fields}) do
    Enum.map_join(fields, ", ", fn %RecordField{name: name} = field ->
      "\"#{name}\" => Encoder.encode_value!(struct.#{name}, #{inspect(field.type)}, @module_prefix)"
    end)
  end

  @spec args_for_from_avro(Template.t()) :: String.t()
  def args_for_from_avro(%Template{fields: fields}) do
    Enum.map_join(fields, ", ", &~s/"#{&1.name}" => #{&1.name}/)
  end

  @spec fields_for_from_avro(Template.t()) :: String.t()
  def fields_for_from_avro(%Template{fields: fields}) do
    Enum.map_join(fields, ", ", fn %RecordField{name: name} = field ->
      "#{name}: Decoder.decode_value!(#{name}, #{inspect(field.type)}, @module_prefix, \"#{name}\")"
    end)
  end
end
