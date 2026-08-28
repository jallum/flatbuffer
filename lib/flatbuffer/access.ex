defmodule Flatbuffer.Access do
  @moduledoc false

  alias Flatbuffer.BadFlatbufferError
  alias Flatbuffer.Utils
  alias Flatbuffer.Reading
  alias Flatbuffer.Cursor

  def get(nil, _, _, _), do: nil

  def get(cursor, key, type, schema) when is_atom(key) or is_binary(key),
    do: get(cursor, [key], type, schema)

  def get(cursor, [], type, schema), do: Reading.read(type, cursor, schema)

  def get(cursor, [key | keys], {:table, %{name: table_name}}, schema)
      when is_atom(key) or is_binary(key) do
    key = if is_atom(key), do: Atom.to_string(key), else: key

    case resolve_field!(schema, table_name, key) do
      {index, {:union_type, union_name}} ->
        cursor
        |> data_pointer(index)
        |> union_index()
        |> case do
          0 ->
            nil

          type_index ->
            {:union, union_definition} = Map.get(schema.entities, union_name)
            Map.get(union_definition.members, type_index - 1)
        end

      {index, {:union, %{name: union_name}}} ->
        cursor
        |> data_pointer(index - 1)
        |> union_index()
        |> case do
          0 ->
            nil

          type_index ->
            {:union, union_definition} = Map.get(schema.entities, union_name)

            case Map.get(union_definition.members, type_index - 1) do
              nil ->
                nil

              union_type ->
                cursor
                |> data_pointer(index)
                |> get(keys, {:table, %{name: union_type}}, schema)
            end
        end

      {index, type} ->
        cursor
        |> data_pointer(index)
        |> get(keys, type, schema)

      nil ->
        nil
    end
  end

  def get(cursor, [index | keys], {:vector, type}, schema) when is_integer(index) do
    vector = Cursor.jump_u32(cursor)
    count = Cursor.get_u32(vector)

    if index >= count do
      nil
    else
      data_pointer = Cursor.skip(vector, 4 + index * Utils.sizeof(type, schema))

      case keys do
        [] -> Reading.read(type, data_pointer, schema)
        _ -> get(data_pointer, keys, type, schema)
      end
    end
  end

  defp resolve_field!(schema, table_name, field_name) do
    case Map.get(schema.entities, table_name) do
      {:table, %{fields: fields, field_ids: field_ids}} ->
        case Map.get(field_ids, field_name) do
          nil ->
            nil

          id ->
            {_output_name, type} = elem(fields, id)
            {id, type}
        end

      _ ->
        raise BadFlatbufferError, message: "Table definition not found: #{table_name}"
    end
  end

  defp data_pointer(cursor, index) do
    table = Cursor.jump_u32(cursor)
    vtable = Cursor.rjump_i32(table)
    entry_offset = 4 + index * 2

    if entry_offset >= Cursor.get_u16(vtable) do
      nil
    else
      case Cursor.skip(vtable, entry_offset) |> Cursor.get_u16() do
        0 -> nil
        data_offset -> Cursor.skip(table, data_offset)
      end
    end
  end

  defp union_index(nil), do: 0
  defp union_index(pointer), do: Cursor.get_u8(pointer)
end
