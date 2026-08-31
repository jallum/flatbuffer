defmodule Flatbuffer.Codegen.Writer do
  @moduledoc false

  alias Flatbuffer.Schema

  def generate(%Schema{} = schema) do
    table_clauses =
      Enum.flat_map(schema.entities, fn
        {name, {:table, %{fields: fields}}} -> [table_clause(name, fields, schema)]
        _entity -> []
      end)

    inline_clauses =
      Enum.flat_map(schema.entities, fn
        {name, {:enum, %{members: members, type: type}}} ->
          [enum_clause(name, members, type)]

        {name, {:struct, %{layout: layout, size: size}}} ->
          [struct_clause(name, layout, size, schema)]

        _entity ->
          []
      end)

    entity_size_clauses =
      Enum.flat_map(schema.entities, fn
        {name, {:enum, %{type: type}}} ->
          [entity_measure_clause(:size, :enum, name, scalar_size(type))]

        {name, {:struct, %{size: size}}} ->
          [entity_measure_clause(:size, :struct, name, size)]

        _entity ->
          []
      end)

    entity_alignment_clauses =
      Enum.flat_map(schema.entities, fn
        {name, {:enum, %{type: type}}} ->
          [entity_measure_clause(:alignment, :enum, name, scalar_size(type))]

        {name, {:struct, %{alignment: alignment}}} ->
          [entity_measure_clause(:alignment, :struct, name, alignment)]

        _entity ->
          []
      end)

    root_type = Macro.escape(schema.root_type)
    buffer_id = schema.id || <<0, 0, 0, 0>>

    quote do
      defp __flatbuffer_generated_to_iolist__(%{} = map) do
        {root, state} =
          __flatbuffer_generated_encode__(
            unquote(root_type),
            map,
            [],
            %Flatbuffer.Writer.State{}
          )

        Flatbuffer.Writer.finish(state, root, unquote(buffer_id))
      end

      defp __flatbuffer_generated_to_binary__(%{} = map) do
        map
        |> __flatbuffer_generated_to_iolist__()
        |> IO.iodata_to_binary()
      end

      defp __flatbuffer_generated_encode__(
             {:string, options},
             string,
             _path,
             state
           )
           when is_binary(string) do
        Flatbuffer.Writer.create_string(
          state,
          string,
          Map.get(options, :shared, false)
        )
      end

      defp __flatbuffer_generated_encode__(
             {:vector, type},
             values,
             path,
             state
           )
           when is_list(values) do
        __flatbuffer_generated_create_vector__(state, type, values, path)
      end

      unquote_splicing(table_clauses)

      defp __flatbuffer_generated_encode__({type, _options}, data, path, _state) do
        Flatbuffer.Writer.wrong_type(type, data, path)
      end

      defp __flatbuffer_generated_create_vector__(state, type, values, path) do
        type = Flatbuffer.Writer.without_default(type)

        __flatbuffer_generated_create_vector_contents__(
          state,
          type,
          values,
          path,
          length(values)
        )
      end

      defp __flatbuffer_generated_create_vector_contents__(
             state,
             {type, _options} = element_type,
             values,
             path,
             vector_length
           )
           when type in [:string, :vector, :table] do
        {elements, state, _next_index} =
          Enum.reduce(values, {[], state, 0}, fn value, {elements, state, index} ->
            {offset, state} =
              __flatbuffer_generated_encode__(
                element_type,
                value,
                [[index] | path],
                state
              )

            {[offset | elements], state, index + 1}
          end)

        Flatbuffer.Writer.finish_reference_vector(
          state,
          elements,
          vector_length,
          __flatbuffer_generated_writer_size__(element_type),
          __flatbuffer_generated_writer_alignment__(element_type)
        )
      end

      defp __flatbuffer_generated_create_vector_contents__(
             state,
             type,
             values,
             path,
             vector_length
           ) do
        {elements, _next_index} =
          Enum.map_reduce(values, 0, fn value, index ->
            {
              __flatbuffer_generated_inline__(type, value, [[index] | path]),
              index + 1
            }
          end)

        Flatbuffer.Writer.finish_inline_vector(
          state,
          elements,
          vector_length,
          __flatbuffer_generated_writer_size__(type),
          __flatbuffer_generated_writer_alignment__(type)
        )
      end

      unquote_splicing(inline_clauses)

      defp __flatbuffer_generated_inline__({_type, _options} = type, value, path),
        do: Flatbuffer.Writer.inline_scalar(type, value, path)

      defp __flatbuffer_generated_writer_size__({type, _options})
           when type in [:bool, :byte, :ubyte],
           do: 1

      defp __flatbuffer_generated_writer_size__({type, _options})
           when type in [:short, :ushort],
           do: 2

      defp __flatbuffer_generated_writer_size__({type, _options})
           when type in [:int, :uint, :float],
           do: 4

      defp __flatbuffer_generated_writer_size__({type, _options})
           when type in [:long, :ulong, :double],
           do: 8

      defp __flatbuffer_generated_writer_size__({type, _options})
           when type in [:string, :vector, :table, :union],
           do: 4

      unquote_splicing(entity_size_clauses)

      defp __flatbuffer_generated_writer_size__({type, _options}),
        do: throw({:error, {:unknown_scalar, type}})

      defp __flatbuffer_generated_writer_alignment__({type, _options})
           when type in [:bool, :byte, :ubyte],
           do: 1

      defp __flatbuffer_generated_writer_alignment__({type, _options})
           when type in [:short, :ushort],
           do: 2

      defp __flatbuffer_generated_writer_alignment__({type, _options})
           when type in [:int, :uint, :float, :string, :vector, :table],
           do: 4

      defp __flatbuffer_generated_writer_alignment__({type, _options})
           when type in [:long, :ulong, :double],
           do: 8

      unquote_splicing(entity_alignment_clauses)

      defp __flatbuffer_generated_writer_alignment__({type, _options}),
        do: throw({:error, {:unknown_scalar, type}})
    end
  end

  defp table_clause(name, fields, schema) do
    field_steps =
      fields
      |> Tuple.to_list()
      |> Enum.with_index()
      |> Enum.map(fn {{field_name, type}, id} ->
        field_write(id, field_name, type, schema)
      end)

    preparations = Enum.map(field_steps, &elem(&1, 0))

    emissions =
      field_steps
      |> Enum.sort_by(fn {_preparation, _emission, _location, alignment, id} ->
        {-alignment, -id}
      end)
      |> Enum.map(&elem(&1, 1))

    location_steps =
      field_steps
      |> Enum.reverse()
      |> Enum.map(fn {_preparation, _emission, location, _alignment, id} ->
        collect_location(id, location)
      end)

    quote do
      defp __flatbuffer_generated_encode__(
             {:table, %{name: unquote(name)}},
             map,
             path,
             state
           )
           when is_map(map) do
        unquote_splicing(preparations)
        table_start = state.size
        unquote_splicing(emissions)
        locations = []
        unquote_splicing(location_steps)

        Flatbuffer.Writer.finish_table(state, table_start, locations)
      end
    end
  end

  defp field_write(id, name, {:union_type, union_name}, schema) do
    {:union, %{members: members}} = Map.fetch!(schema.entities, union_name)
    field = field_variable(id)

    preparation =
      quote do
        value = unquote(field_get(name))

        value =
          case Flatbuffer.Writer.normalize_name(value) do
            nil ->
              0

            union_type ->
              case Map.get(unquote(Macro.escape(members)), union_type) do
                nil ->
                  Flatbuffer.Writer.wrong_type(
                    :union,
                    value,
                    [unquote(name)]
                  )

                index ->
                  index + 1
              end
          end

        unquote(field) =
          if value == 0 do
            nil
          else
            __flatbuffer_generated_inline__(
              {:byte, %{default: 0}},
              value,
              [unquote(name) | path]
            )
          end
      end

    {emission, location} = emit_inline_field(field, 1)
    {preparation, emission, location, 1, id}
  end

  defp field_write(
         id,
         name,
         {:union, %{name: union_name, type_key: type_key}},
         schema
       ) do
    {:union, %{members: members}} = Map.fetch!(schema.entities, union_name)
    field = field_variable(id)

    cases =
      members
      |> Enum.filter(fn {index, table_name} -> is_integer(index) and is_binary(table_name) end)
      |> Enum.sort()
      |> Enum.map(fn {_index, table_name} ->
        table_type = Macro.escape({:table, %{name: table_name}})

        quote do
          unquote(table_name) ->
            case unquote(field_get(name)) do
              nil ->
                {nil, state}

              value ->
                {offset, state} =
                  __flatbuffer_generated_encode__(
                    unquote(table_type),
                    value,
                    [unquote(name) | path],
                    state
                  )

                {offset, state}
            end
        end
      end)

    union_case =
      case_ast(
        quote do
          unquote(field_get(type_key))
          |> Flatbuffer.Writer.normalize_name()
        end,
        [
          quote do
            nil -> {nil, state}
          end
          | cases
        ],
        quote do
          unknown ->
            Flatbuffer.Writer.wrong_type(
              :union,
              unknown,
              [unquote(type_key)]
            )
        end
      )

    preparation =
      quote do
        {unquote(field), state} = unquote(union_case)
      end

    {emission, location} = emit_offset_field(field)
    {preparation, emission, location, 4, id}
  end

  defp field_write(id, name, {type, _options} = field_type, _schema)
       when type in [:string, :vector, :table] do
    escaped_type = Macro.escape(field_type)
    field = field_variable(id)

    preparation =
      quote do
        {unquote(field), state} =
          case unquote(field_get(name)) do
            nil ->
              {nil, state}

            value ->
              {offset, state} =
                __flatbuffer_generated_encode__(
                  unquote(escaped_type),
                  value,
                  [unquote(name) | path],
                  state
                )

              {offset, state}
          end
      end

    {emission, location} = emit_offset_field(field)
    {preparation, emission, location, 4, id}
  end

  defp field_write(id, name, type, schema) do
    escaped_type = Macro.escape(type)
    alignment = type_alignment(type, schema)
    field = field_variable(id)

    value_case =
      case type do
        {_type, %{default: default}} ->
          quote do
            value when value == unquote(Macro.escape(default)) ->
              nil
          end

        _type ->
          nil
      end

    clauses =
      [
        quote do
          nil -> nil
        end,
        value_case,
        quote do
          value ->
            data =
              __flatbuffer_generated_inline__(
                unquote(escaped_type),
                value,
                [unquote(name) | path]
              )

            data
        end
      ]
      |> Enum.reject(&is_nil/1)

    field_case =
      case_ast(
        field_get(name),
        clauses,
        nil
      )

    preparation =
      quote do
        unquote(field) = unquote(field_case)
      end

    {emission, location} = emit_inline_field(field, alignment)
    {preparation, emission, location, alignment, id}
  end

  defp field_variable(_id), do: Macro.unique_var(:field, __MODULE__)

  defp field_get(name) when is_atom(name) do
    binary_name = Atom.to_string(name)

    quote do
      case Map.fetch(map, unquote(name)) do
        {:ok, value} -> value
        :error -> Map.get(map, unquote(binary_name))
      end
    end
  end

  defp field_get(name) when is_binary(name) do
    quote do
      case Map.fetch(map, unquote(name)) do
        {:ok, value} ->
          value

        :error ->
          try do
            Map.get(map, String.to_existing_atom(unquote(name)))
          rescue
            ArgumentError -> nil
          end
      end
    end
  end

  defp emit_offset_field(field) do
    location = Macro.unique_var(:location, __MODULE__)

    emission =
      quote do
        {unquote(location), state} =
          case unquote(field) do
            nil ->
              {nil, state}

            offset ->
              {_field_offset, state} =
                Flatbuffer.Writer.push_offset(state, offset)

              {state.size, state}
          end
      end

    {emission, location}
  end

  defp emit_inline_field(field, alignment) do
    location = Macro.unique_var(:location, __MODULE__)

    emission =
      quote do
        {unquote(location), state} =
          case unquote(field) do
            nil ->
              {nil, state}

            data ->
              state =
                Flatbuffer.Writer.push_aligned(
                  state,
                  data,
                  unquote(alignment)
                )

              {state.size, state}
          end
      end

    {emission, location}
  end

  defp collect_location(id, location) do
    quote do
      locations =
        case unquote(location) do
          nil -> locations
          location -> [{unquote(id), location} | locations]
        end
    end
  end

  defp enum_clause(name, members, type) do
    escaped_members = Macro.escape(members)
    escaped_type = Macro.escape(type)

    quote do
      defp __flatbuffer_generated_inline__(
             {:enum, %{name: unquote(name)} = options},
             value,
             path
           ) do
        value = Flatbuffer.Writer.normalize_name(value)

        case Map.get(unquote(escaped_members), value) do
          nil ->
            Flatbuffer.Writer.wrong_type(:enum, value, path)

          index ->
            {scalar_type, scalar_options} = unquote(escaped_type)

            __flatbuffer_generated_inline__(
              {scalar_type, Map.merge(scalar_options, options)},
              index,
              path
            )
        end
      end
    end
  end

  defp struct_clause(name, layout, struct_size, schema) do
    {chunks, end_offset} =
      Enum.map_reduce(layout, 0, fn {field_name, type, offset}, end_offset ->
        padding = zero_padding(offset - end_offset)

        value =
          quote do
            __flatbuffer_generated_inline__(
              unquote(Macro.escape(type)),
              unquote(field_get(field_name)),
              [unquote(field_name) | path]
            )
          end

        chunk =
          case padding do
            <<>> -> value
            _padding -> [Macro.escape(padding), value]
          end

        {chunk, offset + type_size(type, schema)}
      end)

    chunks =
      case zero_padding(struct_size - end_offset) do
        <<>> -> chunks
        padding -> chunks ++ [Macro.escape(padding)]
      end

    quote do
      defp __flatbuffer_generated_inline__(
             {:struct, %{name: unquote(name)}},
             map,
             path
           )
           when is_map(map) do
        unquote(chunks)
      end
    end
  end

  defp entity_measure_clause(:size, kind, name, value) do
    quote do
      defp __flatbuffer_generated_writer_size__({unquote(kind), %{name: unquote(name)}}),
        do: unquote(value)
    end
  end

  defp entity_measure_clause(:alignment, kind, name, value) do
    quote do
      defp __flatbuffer_generated_writer_alignment__({unquote(kind), %{name: unquote(name)}}),
        do: unquote(value)
    end
  end

  defp type_size({:enum, %{name: name}}, schema) do
    {:enum, %{type: type}} = Map.fetch!(schema.entities, name)
    type_size(type, schema)
  end

  defp type_size({:struct, %{name: name}}, schema) do
    {:struct, %{size: size}} = Map.fetch!(schema.entities, name)
    size
  end

  defp type_size({type, _options}, _schema) when type in [:bool, :byte, :ubyte], do: 1
  defp type_size({type, _options}, _schema) when type in [:short, :ushort], do: 2
  defp type_size({type, _options}, _schema) when type in [:int, :uint, :float], do: 4
  defp type_size({type, _options}, _schema) when type in [:long, :ulong, :double], do: 8

  defp type_alignment({:enum, %{name: name}}, schema) do
    {:enum, %{type: type}} = Map.fetch!(schema.entities, name)
    type_alignment(type, schema)
  end

  defp type_alignment({:struct, %{name: name}}, schema) do
    {:struct, %{alignment: alignment}} = Map.fetch!(schema.entities, name)
    alignment
  end

  defp type_alignment({type, _options}, _schema) when type in [:bool, :byte, :ubyte], do: 1
  defp type_alignment({type, _options}, _schema) when type in [:short, :ushort], do: 2

  defp type_alignment({type, _options}, _schema)
       when type in [:int, :uint, :float, :string, :vector, :table],
       do: 4

  defp type_alignment({type, _options}, _schema) when type in [:long, :ulong, :double], do: 8

  defp scalar_size({type, _options}), do: Flatbuffer.Utils.scalar_size(type)

  defp zero_padding(0), do: <<>>
  defp zero_padding(size), do: :binary.copy(<<0>>, size)

  defp case_ast(subject, clauses, nil), do: {:case, [], [subject, [do: Enum.concat(clauses)]]}

  defp case_ast(subject, clauses, fallback),
    do: {:case, [], [subject, [do: Enum.concat(clauses ++ [fallback])]]}
end
