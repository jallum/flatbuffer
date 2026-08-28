defmodule Flatbuffer.Writer do
  @moduledoc false

  alias Flatbuffer.Utils

  def to_i8(i8), do: <<i8::signed-8>>
  def to_u8(u8), do: <<u8::unsigned-8>>
  def to_i16(i16), do: <<i16::signed-little-16>>
  def to_u16(u16), do: <<u16::unsigned-little-16>>
  def to_i32(i32), do: <<i32::signed-little-32>>
  def to_u32(u32), do: <<u32::unsigned-little-32>>
  def to_i64(i64), do: <<i64::signed-little-64>>
  def to_u64(u64), do: <<u64::unsigned-little-64>>
  def to_f32(f32), do: <<f32::float-little-32>>
  def to_f64(f64), do: <<f64::float-little-64>>

  def write({_, %{default: same}}, same, _, _), do: []

  # def write({_, _}, nil, _, _) do
  #   []
  # end

  def write({:bool, _options}, true, _, _), do: to_u8(1)
  def write({:bool, _options}, false, _, _), do: to_u8(0)

  def write({:byte, _options}, i8, _, _)
      when is_integer(i8) and i8 >= -128 and i8 <= 127,
      do: to_i8(i8)

  def write({:ubyte, _options}, u8, _, _)
      when is_integer(u8) and u8 >= 0 and u8 <= 255,
      do: to_u8(u8)

  def write({:short, _options}, i16, _, _)
      when is_integer(i16) and i16 <= 32_767 and i16 >= -32_768,
      do: to_i16(i16)

  def write({:ushort, _options}, u16, _, _)
      when is_integer(u16) and u16 >= 0 and u16 <= 65536,
      do: to_u16(u16)

  def write({:int, _options}, i32, _, _)
      when is_integer(i32) and i32 >= -2_147_483_648 and i32 <= 2_147_483_647,
      do: to_i32(i32)

  def write({:uint, _options}, u32, _, _)
      when is_integer(u32) and u32 >= 0 and u32 <= 4_294_967_295,
      do: to_u32(u32)

  def write({:float, _options}, f32, _, _)
      when is_number(f32) and f32 >= -3.4e+38 and f32 <= +3.4e+38,
      do: to_f32(f32)

  def write({:long, _options}, i64, _, _)
      when is_integer(i64) and i64 >= -9_223_372_036_854_775_808 and
             i64 <= 9_223_372_036_854_775_807,
      do: to_i64(i64)

  def write({:ulong, _options}, u64, _, _)
      when is_integer(u64) and u64 >= 0 and u64 <= 18_446_744_073_709_551_615,
      do: to_u64(u64)

  def write({:double, _options}, f64, _, _)
      when is_number(f64) and f64 >= -1.7e+308 and f64 <= +1.7e+308,
      do: to_f64(f64)

  # complex types

  def write({:struct, %{name: struct_name}}, map, _, schema) when is_map(map) do
    {:struct, %{members: members}} = Map.get(schema.entities, struct_name)

    members
    |> Enum.map(fn {field_name, field_type} ->
      value = get_field(map, field_name)
      write({field_type, %{}}, value, [struct_name, field_name], schema)
    end)
  end

  def write({:string, _options}, string, _, _) when is_binary(string) do
    <<byte_size(string)::unsigned-little-size(32)>> <> string
  end

  def write({:vector, {type, type_options}}, values, path, schema)
      when is_list(values) do
    vector_length = length(values)
    # we are putting the indices as [i] as a type
    # so if something goes wrong it's easy to see
    # that it was a vector index
    type_options_without_default = Map.delete(type_options, :default)

    index_types =
      case vector_length do
        0 ->
          []

        _ ->
          for i <- 0..(vector_length - 1) do
            {[i], {type, type_options_without_default}}
          end
      end

    [<<vector_length::little-size(32)>>, data_buffer_and_data(index_types, values, path, schema)]
  end

  def write({:enum, %{name: enum_name} = options}, value, path, schema)
      when is_atom(value) or is_binary(value) do
    {:enum, %{members: members, type: {type, type_options}}} = Map.get(schema.entities, enum_name)

    # if we got handed some defaults from outside,
    # we put them in here
    type_options = Map.merge(type_options, options)
    value = if is_atom(value), do: Atom.to_string(value), else: value
    index = Map.get(members, value)

    case index do
      nil -> throw({:error, {:not_in_enum, value, members}})
      _ -> write({type, type_options}, index, path, schema)
    end
  end

  # write a complete table
  def write({:table, %{name: table_name}}, map, path, schema)
      when is_map(map) do
    {:table, %{fields: fields}} = Map.get(schema.entities, table_name)

    {names_types, values} =
      Enum.reduce(
        fields |> Tuple.to_list() |> Enum.reverse(),
        {[], []},
        fn
          {name, {:union_type, union_name}}, {type_acc, value_acc} ->
            {:union, %{members: members}} = Map.get(schema.entities, union_name)

            case get_field(map, name) do
              nil ->
                type_acc_new = [{{name}, {:byte, %{default: 0}}} | type_acc]
                value_acc_new = [0 | value_acc]
                {type_acc_new, value_acc_new}

              union_type ->
                union_type = normalize_name(union_type)
                union_index = Map.get(members, union_type)

                {[{{name}, {:byte, %{default: 0}}} | type_acc], [union_index + 1 | value_acc]}
            end

          {name, {:union, %{type_key: type_key}} = type}, {type_acc, value_acc} ->
            union_type = map |> get_field(type_key) |> normalize_name()

            field_type =
              case union_type do
                nil -> type
                union_type -> {:table, %{name: union_type}}
              end

            {[{{name}, field_type} | type_acc], [get_field(map, name) | value_acc]}

          {name, type}, {type_acc, value_acc} ->
            {[{{name}, type} | type_acc], [get_field(map, name) | value_acc]}
        end
      )

    # we are putting the keys as {key} as a type
    # so if something goes wrong it's easy to see
    # that it was a map key
    [data_buffer, data] = data_buffer_and_data(names_types, values, path, schema)
    vtable = vtable(data_buffer)
    springboard = <<:erlang.iolist_size(vtable) + 4::little-size(32)>>
    data_buffer_length = <<:erlang.iolist_size([springboard, data_buffer])::little-size(16)>>
    vtable_length = <<:erlang.iolist_size([vtable, springboard])::little-size(16)>>
    [vtable_length, data_buffer_length, vtable, springboard, data_buffer, data]
  end

  # fail if nothing matches
  def write({type, _}, data, path, _) do
    throw({:error, {:wrong_type, type, data, Enum.reverse(path)}})
  end

  # build up [data_buffer, data]
  # as part of a table or vector
  def data_buffer_and_data(types, values, path, schema) do
    data_buffer_and_data(types, values, path, schema, {[], [], 0})
  end

  def data_buffer_and_data([], [], _path, _schema, {data_buffer, data, _}) do
    [adjust_for_length(data_buffer), Enum.reverse(data)]
  end

  # value is nil so we put a null pointer
  def data_buffer_and_data(
        [_type | types],
        [nil | values],
        path,
        schema,
        {scalar_and_pointers, data, data_offset}
      ) do
    data_buffer_and_data(
      types,
      values,
      path,
      schema,
      {[[] | scalar_and_pointers], data, data_offset}
    )
  end

  def data_buffer_and_data(
        [{name, type} | types],
        [value | values],
        path,
        schema,
        {scalar_and_pointers, data, data_offset}
      ) do
    # for clean error reporting we
    # need to accumulate the names of tables (depth)
    # but not the indices for vectors (width)
    case Utils.scalar?(type) do
      true ->
        scalar_data = write(type, value, [name | path], schema)

        data_buffer_and_data(
          types,
          values,
          path,
          schema,
          {[scalar_data | scalar_and_pointers], data, data_offset}
        )

      false ->
        complex_data = write(type, value, [name | path], schema)
        complex_data_length = :erlang.iolist_size(complex_data)
        # for a table we do not point to the start but to the springboard
        data_pointer =
          case type do
            {:table, _} ->
              [vtable_length, data_buffer_length, vtable | _] = complex_data

              table_header_offset =
                :erlang.iolist_size([vtable_length, data_buffer_length, vtable])

              data_offset + table_header_offset

            _ ->
              data_offset
          end

        data_buffer_and_data(
          types,
          values,
          path,
          schema,
          {[data_pointer | scalar_and_pointers], [complex_data | data],
           complex_data_length + data_offset}
        )
    end
  end

  # so this is a mix of scalars (binary)
  # and unadjusted pointers (integers)
  # we adjust the pointers to account
  # for their poisition in the buffer
  def adjust_for_length(data_buffer) do
    adjust_for_length(data_buffer, {[], 0})
  end

  def adjust_for_length([], {acc, _}) do
    acc
  end

  # this is null pointers, we pass
  def adjust_for_length([[] | data_buffer], {acc, offset}) do
    adjust_for_length(data_buffer, {[[] | acc], offset})
  end

  # this is a scalar, we just pass the data
  def adjust_for_length([scalar | data_buffer], {acc, offset}) when is_binary(scalar) do
    adjust_for_length(data_buffer, {[scalar | acc], offset + byte_size(scalar)})
  end

  # referenced data, we get it and recurse
  def adjust_for_length([pointer | data_buffer], {acc, offset}) when is_integer(pointer) do
    offset_new = offset + 4
    pointer_bin = <<pointer + offset_new::little-size(32)>>
    adjust_for_length(data_buffer, {[pointer_bin | acc], offset_new})
  end

  # we get a nested structure so we pass it untouched
  def adjust_for_length([iolist | data_buffer], {acc, offset}) when is_list(iolist) do
    adjust_for_length(data_buffer, {[iolist | acc], offset + 4})
  end

  def vtable(data_buffer) do
    Enum.reverse(vtable(data_buffer, {[], 4}))
  end

  def vtable([], {acc, _offset}) do
    acc
  end

  def vtable([data | data_buffer], {acc, offset}) do
    case data do
      [] ->
        # this is an undefined value, we put a null pointer
        # and leave the offset untouched
        vtable(data_buffer, {[<<0::little-size(16)>> | acc], offset})

      scalar_or_pointer ->
        vtable(
          data_buffer,
          {[<<offset::little-size(16)>> | acc], offset + :erlang.iolist_size(scalar_or_pointer)}
        )
    end
  end

  defp get_field(map, name) do
    case Map.fetch(map, name) do
      {:ok, value} ->
        value

      :error when is_binary(name) ->
        try do
          Map.get(map, String.to_existing_atom(name))
        rescue
          ArgumentError -> nil
        end

      :error when is_atom(name) ->
        Map.get(map, Atom.to_string(name))
    end
  end

  defp normalize_name(nil), do: nil
  defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_name(name), do: name

  def scalar?(:string), do: false
  def scalar?({:vector, _}), do: false
  def scalar?({:table, _}), do: false
  def scalar?({:enum, _}), do: true
  def scalar?(_), do: true
end
