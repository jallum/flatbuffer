defmodule Flatbuffer.Reading do
  @moduledoc false

  alias Flatbuffer.Utils
  alias Flatbuffer.Cursor

  @spec check_buffer_id(Cursor.t(), binary() | nil) ::
          :ok | {:error, {:id_mismatch, %{data: binary(), schema: binary()}}}
  def check_buffer_id(_cursor, nil), do: :ok

  def check_buffer_id(cursor, id) do
    case cursor |> Cursor.skip(4) |> Cursor.get_bytes(4) do
      ^id -> :ok
      data_id -> {:error, {:id_mismatch, %{data: data_id, schema: id}}}
    end
  end

  def read({:bool, _}, c, _), do: Cursor.get_i8(c) != 0
  def read({:byte, _}, c, _), do: Cursor.get_i8(c)
  def read({:ubyte, _}, c, _), do: Cursor.get_u8(c)
  def read({:short, _}, c, _), do: Cursor.get_i16(c)
  def read({:ushort, _}, c, _), do: Cursor.get_u16(c)
  def read({:int, _}, c, _), do: Cursor.get_i32(c)
  def read({:uint, _}, c, _), do: Cursor.get_u32(c)
  def read({:long, _}, c, _), do: Cursor.get_i64(c)
  def read({:ulong, _}, c, _), do: Cursor.get_u64(c)
  def read({:float, _}, c, _), do: Cursor.get_f32(c)
  def read({:double, _}, c, _), do: Cursor.get_f64(c)

  def read({:string, _options}, c, _) do
    c = Cursor.jump_u32(c)
    Cursor.get_bytes(Cursor.skip(c, 4), Cursor.get_u32(c))
  end

  def read({:vector, type}, c, schema) do
    c = Cursor.jump_u32(c)
    read_vector(type, Cursor.get_u32(c), Cursor.skip(c, 4), Utils.sizeof(type, schema), schema)
  end

  def read({:enum, %{name: enum_name}}, c, schema) do
    {:enum, %{members: members, type: type}} = Map.get(schema.entities, enum_name)
    index = read(type, c, schema)

    case Map.get(members, index) do
      nil -> throw({:error, {:not_in_enum, index, members}})
      value -> value
    end
  end

  def read({:struct, %{name: struct_name}}, c, schema) do
    {:struct, %{layout: layout}} = Map.fetch!(schema.entities, struct_name)

    Enum.reduce(layout, %{}, fn {name, type, offset}, struct ->
      Map.put(struct, name, read(type, Cursor.skip(c, offset), schema))
    end)
  end

  def read({:table, %{name: table_name}}, c, schema) do
    {:table, %{fields: fields}} = Map.get(schema.entities, table_name)

    table = Cursor.jump_u32(c)
    vtable = Cursor.rjump_i32(table)
    count = div(Cursor.get_u16(vtable) - 4, 2)

    read_table(%{}, count, Tuple.to_list(fields), Cursor.skip(vtable, 4), table, schema)
  end

  def read(type, _, _), do: throw({:error, {:unknown_type, type}})

  # Vectors

  defp read_vector(_, 0, _, _, _), do: []

  defp read_vector(type, count, c, size, schema) do
    [
      read(type, c, schema)
      | read_vector(type, count - 1, Cursor.skip(c, size), size, schema)
    ]
  end

  # Tables

  # we might still have more fields but we ran out of vtable slots
  # this happens if the schema has more fields than the data (schema evolution)
  defp read_table(row, 0, _, _, _, _), do: row

  # we might have more data but no more fields
  # that means the data is ahead and has more data than the schema
  defp read_table(row, _, [], _, _, _), do: row

  defp read_table(
         row,
         count,
         [{name, {:union_type, union_name}} | fields],
         vtable,
         table,
         schema
       ) do
    data_offset = Cursor.get_u16(vtable)
    index = if data_offset == 0, do: 0, else: Cursor.skip(table, data_offset) |> Cursor.get_u8()

    row =
      if index > 0 do
        {:union, %{members: members}} = Map.get(schema.entities, union_name)

        case Map.get(members, index - 1) do
          nil -> row
          table_name -> Map.put(row, name, table_name)
        end
      else
        row
      end

    read_table(row, count - 1, fields, Cursor.skip(vtable, 2), table, schema)
  end

  defp read_table(
         row,
         count,
         [{name, {:union, %{type_key: type_key}}} | fields],
         vtable,
         table,
         schema
       ) do
    data_offset = Cursor.get_u16(vtable)

    row =
      case {data_offset, Map.get(row, type_key)} do
        {0, _} ->
          row

        {_, nil} ->
          row

        {_, table_name} ->
          value = read({:table, %{name: table_name}}, Cursor.skip(table, data_offset), schema)
          Map.put(row, name, value)
      end

    read_table(row, count - 1, fields, Cursor.skip(vtable, 2), table, schema)
  end

  defp read_table(
         row,
         count,
         [{name, type} | fields],
         vtable,
         table,
         schema
       ) do
    data_offset = Cursor.get_u16(vtable)

    row =
      if data_offset != 0 do
        value = read(type, Cursor.skip(table, data_offset), schema)
        Map.put(row, name, value)
      else
        case type do
          {_type, %{default: default}} ->
            Map.put(row, name, default)

          {_type, _options} ->
            row
        end
      end

    read_table(row, count - 1, fields, Cursor.skip(vtable, 2), table, schema)
  end
end
