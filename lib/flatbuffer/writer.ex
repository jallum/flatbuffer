defmodule Flatbuffer.Writer do
  @moduledoc false

  defmodule State do
    @moduledoc false

    defstruct chunks: [], size: 0, min_align: 1, strings: %{}, vtables: %{}
  end

  def to_iolist(%{} = map, schema) do
    {root, state} = encode(schema.root_type, map, [], schema, %State{})
    buffer_id = schema.id || <<0, 0, 0, 0>>
    state = pre_align(state, 4 + byte_size(buffer_id), state.min_align)
    state = push_raw(state, buffer_id)
    {_root_reference, state} = push_offset(state, root)
    state.chunks
  end

  defp encode({:string, options}, string, _path, _schema, state) when is_binary(string) do
    create_string(state, string, Map.get(options, :shared, false))
  end

  defp encode({:vector, type}, values, path, schema, state) when is_list(values) do
    create_vector(state, type, values, path, schema)
  end

  defp encode({:table, %{name: table_name}}, map, path, schema, state) when is_map(map) do
    create_table(state, table_name, map, path, schema)
  end

  defp encode({type, _options}, data, path, _schema, _state) do
    wrong_type(type, data, path)
  end

  defp create_string(%State{strings: strings} = state, string, true) do
    case Map.fetch(strings, string) do
      {:ok, offset} ->
        {offset, state}

      :error ->
        {offset, state} = emit_string(state, string)
        {offset, %{state | strings: Map.put(strings, string, offset)}}
    end
  end

  defp create_string(state, string, false), do: emit_string(state, string)

  defp emit_string(state, string) do
    state = pre_align(state, byte_size(string) + 1, 4)
    state = push_raw(state, <<0>>)
    state = push_raw(state, string)
    state = push_raw(state, <<byte_size(string)::unsigned-little-32>>)
    {state.size, state}
  end

  defp create_vector(state, type, values, path, schema) do
    type = without_default(type)
    create_vector_contents(state, type, values, path, schema, length(values))
  end

  defp create_vector_contents(
         state,
         {type, _} = element_type,
         values,
         path,
         schema,
         vector_length
       )
       when type in [:string, :vector, :table] do
    {elements, state, _next_index} =
      Enum.reduce(values, {[], state, 0}, fn value, {elements, state, index} ->
        {offset, state} = encode(element_type, value, [[index] | path], schema, state)

        {[offset | elements], state, index + 1}
      end)

    state = align_vector(state, element_type, vector_length, schema)

    state =
      Enum.reduce(elements, state, fn offset, state ->
        {_field_offset, state} = push_offset(state, offset)
        state
      end)

    state = push_raw(state, <<vector_length::unsigned-little-32>>)
    {state.size, state}
  end

  defp create_vector_contents(state, type, values, path, schema, vector_length) do
    {elements, _next_index} =
      Enum.map_reduce(values, 0, fn value, index ->
        {inline(type, value, [[index] | path], schema), index + 1}
      end)

    state = align_vector(state, type, vector_length, schema)
    state = push_raw(state, elements)
    state = push_raw(state, <<vector_length::unsigned-little-32>>)
    {state.size, state}
  end

  defp align_vector(state, type, vector_length, schema) do
    element_size = Flatbuffer.Utils.sizeof(type, schema)
    payload_size = vector_length * element_size
    state = pre_align(state, payload_size, 4)
    pre_align(state, payload_size, alignment(type, schema))
  end

  defp create_table(state, table_name, map, path, schema) do
    {:table, %{fields: fields}} = Map.fetch!(schema.entities, table_name)

    {prepared_fields, state} =
      prepare_table_fields(fields, 0, map, path, schema, [], state)

    emit_table(state, prepared_fields, schema)
  end

  defp prepare_table_fields(fields, id, _map, _path, _schema, prepared, state)
       when id == tuple_size(fields),
       do: {prepared, state}

  defp prepare_table_fields(fields, id, map, path, schema, prepared, state) do
    {name, type} = elem(fields, id)
    {type, value} = table_field(type, name, map, schema)

    {prepared, state} =
      prepare_table_field(id, name, type, value, path, schema, prepared, state)

    prepare_table_fields(fields, id + 1, map, path, schema, prepared, state)
  end

  defp prepare_table_field(
         _id,
         _name,
         _type,
         nil,
         _path,
         _schema,
         prepared,
         state
       ),
       do: {prepared, state}

  defp prepare_table_field(
         _id,
         _name,
         {_type, %{default: default}},
         default,
         _path,
         _schema,
         prepared,
         state
       ),
       do: {prepared, state}

  defp prepare_table_field(
         id,
         name,
         {type, _} = field_type,
         value,
         path,
         schema,
         prepared,
         state
       )
       when type in [:string, :vector, :table] do
    {offset, state} = encode(field_type, value, [name | path], schema, state)
    {[{id, {:offset, offset}} | prepared], state}
  end

  defp prepare_table_field(id, name, type, value, path, schema, prepared, state) do
    data = inline(type, value, [name | path], schema)
    {[{id, {:inline, data, type}} | prepared], state}
  end

  defp table_field({:union_type, union_name}, name, map, schema) do
    value = get_field(map, name)
    {:union, %{members: members}} = Map.fetch!(schema.entities, union_name)

    encoded =
      case normalize_name(value) do
        nil ->
          0

        union_type ->
          case Map.get(members, union_type) do
            nil -> wrong_type(:union, value, [name])
            index -> index + 1
          end
      end

    {{:byte, %{default: 0}}, encoded}
  end

  defp table_field({:union, %{type_key: type_key}} = type, name, map, _schema) do
    case map |> get_field(type_key) |> normalize_name() do
      nil -> {type, nil}
      table_name -> {{:table, %{name: table_name}}, get_field(map, name)}
    end
  end

  defp table_field(type, name, map, _schema), do: {type, get_field(map, name)}

  defp emit_table(state, fields, schema) do
    table_start = state.size

    {locations, state} = Enum.reduce(fields, {[], state}, &emit_table_field(&1, &2, schema))

    state = align(state, 4)
    table_offset = state.size + 4
    object_size = table_offset - table_start
    layout = vtable_layout(locations, table_offset, 0)
    vtable_key = {object_size, layout}

    case Map.fetch(state.vtables, vtable_key) do
      {:ok, vtable_offset} ->
        displacement = vtable_offset - table_offset
        state = push_raw(state, <<displacement::signed-little-32>>)
        {table_offset, state}

      :error ->
        {vtable_size, vtable} = encode_vtable(object_size, layout)
        state = push_raw(state, <<vtable_size::signed-little-32>>)
        state = push_raw(state, vtable)
        vtable_offset = state.size
        state = %{state | vtables: Map.put(state.vtables, vtable_key, vtable_offset)}
        {table_offset, state}
    end
  end

  defp emit_table_field({id, {:offset, offset}}, {locations, state}, _schema) do
    {_field_offset, state} = push_offset(state, offset)
    {[{id, state.size} | locations], state}
  end

  defp emit_table_field(
         {id, {:inline, data, type}},
         {locations, state},
         schema
       ) do
    state = push_aligned(state, data, alignment(type, schema))
    {[{id, state.size} | locations], state}
  end

  defp vtable_layout([], _table_offset, _id), do: []

  defp vtable_layout([{id, location} | locations], table_offset, id),
    do: [table_offset - location | vtable_layout(locations, table_offset, id + 1)]

  defp vtable_layout(locations, table_offset, id),
    do: [0 | vtable_layout(locations, table_offset, id + 1)]

  defp encode_vtable(object_size, layout) do
    vtable_size = 4 + length(layout) * 2
    entries = Enum.map(layout, &<<&1::unsigned-little-16>>)

    {vtable_size, [<<vtable_size::unsigned-little-16, object_size::unsigned-little-16>>, entries]}
  end

  defp inline({:enum, %{name: enum_name} = options}, value, path, schema) do
    {:enum, %{members: members, type: {type, type_options}}} =
      Map.fetch!(schema.entities, enum_name)

    value = normalize_name(value)

    case Map.get(members, value) do
      nil -> wrong_type(:enum, value, path)
      index -> inline({type, Map.merge(type_options, options)}, index, path, schema)
    end
  end

  defp inline({:struct, %{name: struct_name}}, map, path, schema) when is_map(map) do
    {:struct, %{members: members}} = Map.fetch!(schema.entities, struct_name)

    Enum.map(members, fn {name, type} ->
      inline({type, %{}}, get_field(map, name), [name | path], schema)
    end)
  end

  defp inline({:bool, _}, true, _path, _schema), do: <<1>>
  defp inline({:bool, _}, false, _path, _schema), do: <<0>>

  defp inline({:byte, _}, value, _path, _schema)
       when is_integer(value) and value >= -128 and value <= 127,
       do: <<value::signed-8>>

  defp inline({:ubyte, _}, value, _path, _schema)
       when is_integer(value) and value >= 0 and value <= 255,
       do: <<value::unsigned-8>>

  defp inline({:short, _}, value, _path, _schema)
       when is_integer(value) and value >= -32_768 and value <= 32_767,
       do: <<value::signed-little-16>>

  defp inline({:ushort, _}, value, _path, _schema)
       when is_integer(value) and value >= 0 and value <= 65_535,
       do: <<value::unsigned-little-16>>

  defp inline({:int, _}, value, _path, _schema)
       when is_integer(value) and value >= -2_147_483_648 and value <= 2_147_483_647,
       do: <<value::signed-little-32>>

  defp inline({:uint, _}, value, _path, _schema)
       when is_integer(value) and value >= 0 and value <= 4_294_967_295,
       do: <<value::unsigned-little-32>>

  defp inline({:float, _}, value, _path, _schema)
       when is_number(value) and value >= -3.4e+38 and value <= 3.4e+38,
       do: <<value::float-little-32>>

  defp inline({:long, _}, value, _path, _schema)
       when is_integer(value) and value >= -9_223_372_036_854_775_808 and
              value <= 9_223_372_036_854_775_807,
       do: <<value::signed-little-64>>

  defp inline({:ulong, _}, value, _path, _schema)
       when is_integer(value) and value >= 0 and value <= 18_446_744_073_709_551_615,
       do: <<value::unsigned-little-64>>

  defp inline({:double, _}, value, _path, _schema)
       when is_number(value) and value >= -1.7e+308 and value <= 1.7e+308,
       do: <<value::float-little-64>>

  defp inline({type, _}, value, path, _schema), do: wrong_type(type, value, path)

  defp without_default({type, options}) when is_map(options),
    do: {type, Map.delete(options, :default)}

  defp without_default(type), do: type

  defp alignment({:enum, %{name: enum_name}}, schema) do
    {:enum, %{type: type}} = Map.fetch!(schema.entities, enum_name)
    alignment(type, schema)
  end

  defp alignment({:struct, _}, _schema), do: 1
  defp alignment({type, _}, _schema) when type in [:string, :vector, :table], do: 4
  defp alignment({type, _}, _schema), do: Flatbuffer.Utils.scalar_size(type)
  defp alignment(type, _schema), do: Flatbuffer.Utils.scalar_size(type)

  defp push_raw(%State{} = state, data) when is_binary(data),
    do: %{state | chunks: [data | state.chunks], size: state.size + byte_size(data)}

  defp push_raw(%State{} = state, data),
    do: %{state | chunks: [data | state.chunks], size: state.size + :erlang.iolist_size(data)}

  defp push_offset(state, target) do
    state = align(state, 4)
    offset = state.size - target + 4
    state = push_raw(state, <<offset::unsigned-little-32>>)
    {state.size, state}
  end

  defp push_aligned(state, data, alignment) do
    state
    |> align(alignment)
    |> push_raw(data)
  end

  defp align(state, alignment), do: pre_align(state, 0, alignment)

  defp pre_align(state, future_size, alignment) do
    padding = Integer.mod(-(state.size + future_size), alignment)
    state = track_alignment(state, alignment)

    case padding do
      0 -> state
      bytes -> push_raw(state, :binary.copy(<<0>>, bytes))
    end
  end

  defp track_alignment(%State{min_align: current} = state, alignment)
       when current >= alignment,
       do: state

  defp track_alignment(state, alignment), do: %{state | min_align: alignment}

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

  defp wrong_type(type, data, path),
    do: throw({:error, {:wrong_type, type, data, Enum.reverse(path)}})
end
