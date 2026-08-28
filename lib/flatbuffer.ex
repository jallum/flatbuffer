defmodule Flatbuffer do
  @moduledoc ~S"""
  Flatbuffer binary serialization for Elixir.

  Provides functions to read from and write to Flatbuffer binaries using schema definitions.
  Supports direct access to nested data without parsing the entire buffer.

  ## Usage
      # Read/Write
      {:ok, data} = Flatbuffer.read(buffer, schema)
      binary = Flatbuffer.to_binary(map, schema)

      # Direct access
      value = Flatbuffer.get(buffer, [:table, :field], schema)

      # With schema file
      def YourThing do
        use Flatbuffer, file: "schema.fbs"
      end

      # Read/Write
      {:ok, data} = YourThing.read(buffer)
      binary = YourThing.to_binary(map)

  """

  alias Flatbuffer.BadFlatbufferError
  alias Flatbuffer.Access
  alias Flatbuffer.Cursor
  alias Flatbuffer.Reading
  alias Flatbuffer.Schema
  alias Flatbuffer.Writer

  @type field_key :: String.t() | atom()
  @type path :: field_key() | [field_key() | non_neg_integer()]

  @doc """
  Reads a Flatbuffer into a map using the given schema. Field, struct, and enum
  names are atoms by default, or binaries when the schema was built with
  `safe: true`.
  Returns {:ok, map} or {:error, reason}.
  """
  @spec read(buffer :: iodata(), Schema.t()) ::
          {:ok, map()}
          | {:error, {:id_mismatch, %{buffer_id: binary(), schema_id: binary()}}}
  def read(buffer, %Schema{} = schema) do
    cursor = Cursor.wrap(buffer)

    with :ok <- Reading.check_buffer_id(cursor, schema.id) do
      {:ok, Reading.read(schema.root_type, cursor, schema)}
    end
  end

  @doc """
  Same as read/2 but raises on error.
  """
  @spec read!(buffer :: iodata(), Schema.t()) :: map()
  def read!(buffer, %Schema{} = schema) do
    with {:ok, value} <- read(buffer, schema) do
      value
    else
      {:error, _reason} = error -> throw(error)
    end
  end

  @doc """
  Gets the value for a specific key without decoding the entire buffer.

  Both atom and binary field names are accepted. Lookup never creates atoms.

  If the key (or path) is present in the buffer then its value value is
  returned. Otherwise, `default` is returned.

  If `default` is not provided, `nil` is used.

  If an unparseable buffer is provided, an BadFlatbufferError is raised.
  """
  @spec get(
          buffer :: iodata(),
          path(),
          Schema.t(),
          nil | default
        ) :: default
        when default: term()
  def get(buffer, path, schema, default \\ nil) do
    buffer
    |> Cursor.wrap()
    |> Access.get(path, schema.root_type, schema) || default
  catch
    error ->
      raise BadFlatbufferError, message: "Failed to read Flatbuffer: #{inspect(error)}"
  end

  @doc """
  Fetches the value for a specific key (or key path) without decoding the entire
  buffer.

  If the buffer contains the key/path, then its value is returned in the shape
  of `{:ok, value}`. If the value cannot be found, `:error` is returned. If the
  buffer does not pass the id-check, `{:error, {:id_mismatch, {buffer_id, schema_id}}}`
  """
  @spec fetch(buffer :: iodata(), path(), Schema.t()) :: any()
  def fetch(buffer, path, schema) do
    case get(buffer, path, schema) do
      nil -> :error
      value -> {:ok, value}
    end
  end

  @doc """
  Fetches the value for a specific key (or key path) without decoding the entire
  buffer.

  If the buffer contains the key/path, the corresponding value is returned. If
  buffer doesn't contain it, a `KeyError` exception is raised.
  """
  @spec fetch!(buffer :: iodata(), path(), Schema.t()) :: any()
  def fetch!(buffer, path, schema) do
    case get(buffer, path, schema) do
      nil -> raise KeyError, term: buffer, key: path
      value -> value
    end
  end

  @doc """
  Serializes a map into a Flatbuffer iolist using the schema. Both atom and
  binary field names are accepted.
  """
  @spec to_iolist(map(), Schema.t()) :: iolist()
  def to_iolist(%{} = map, %Schema{} = schema) do
    root_table =
      [<<vtable_offset::little-size(16)>> | _] =
      Writer.write(schema.root_type, map, [], schema)

    buffer_id = schema.id || <<0, 0, 0, 0>>

    [
      <<vtable_offset + 4 + byte_size(buffer_id)::little-size(32)>>,
      buffer_id,
      root_table
    ]
  end

  @doc """
  Serializes a map into a Flatbuffer binary using the schema.
  """
  @spec to_binary(map(), Schema.t()) :: binary()
  def to_binary(%{} = map, %Schema{} = schema) do
    map
    |> to_iolist(schema)
    |> IO.iodata_to_binary()
  end

  @doc """
  Generates schema-aware functions (read, get, to_iolist, etc.) in the caller module.
  Options:
    * :file - Required schema file path.
    * :path - Base path for schema includes.
    * :safe - Decode schema-defined names as binaries instead of atoms. Defaults to `false`.
  """
  defmacro __using__(opts) do
    resolver =
      case Keyword.get(opts, :path) do
        nil -> &File.read/1
        path -> &File.read(Path.join(path, &1))
      end

    file = Keyword.get(opts, :file) || raise "Missing :file option"

    with {:ok, schema} <-
           Schema.from_file(file, resolver: resolver, safe: Keyword.get(opts, :safe, false)) do
      quote do
        def schema, do: unquote(Macro.escape(schema))
        def read(buffer), do: Flatbuffer.read(buffer, schema())
        def read!(buffer), do: Flatbuffer.read!(buffer, schema())
        def get(buffer, path, default \\ nil), do: Flatbuffer.get(buffer, path, schema(), default)
        def fetch(buffer, path), do: Flatbuffer.fetch(buffer, path, schema())
        def fetch!(buffer, path), do: Flatbuffer.fetch!(buffer, path, schema())
        def to_iolist(map), do: Flatbuffer.to_iolist(map, schema())
        def to_binary(map), do: Flatbuffer.to_binary(map, schema())
      end
    else
      {:error, reason} -> raise "Failed to load schema from file (#{file}): #{inspect(reason)}"
    end
  end
end
