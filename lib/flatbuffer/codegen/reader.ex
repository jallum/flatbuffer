defmodule Flatbuffer.Codegen.Reader do
  @moduledoc false

  alias Flatbuffer.Codegen.Schema, as: CodegenSchema
  alias Flatbuffer.Schema

  @scalar_types [
    :bool,
    :byte,
    :ubyte,
    :short,
    :ushort,
    :int,
    :uint,
    :long,
    :ulong,
    :float,
    :double
  ]
  @decoder_types [:i8, :u8, :i16, :u16, :i32, :u32, :i64, :u64, :f32, :f64]
  @decoder_by_scalar %{
    bool: :i8,
    byte: :i8,
    ubyte: :u8,
    short: :i16,
    ushort: :u16,
    int: :i32,
    uint: :u32,
    long: :i64,
    ulong: :u64,
    float: :f32,
    double: :f64
  }
  @decoder_function %{
    i8: :__flatbuffer_generated_i8__,
    u8: :__flatbuffer_generated_u8__,
    i16: :__flatbuffer_generated_i16__,
    u16: :__flatbuffer_generated_u16__,
    i32: :__flatbuffer_generated_i32__,
    u32: :__flatbuffer_generated_u32__,
    i64: :__flatbuffer_generated_i64__,
    u64: :__flatbuffer_generated_u64__,
    f32: :__flatbuffer_generated_f32__,
    f64: :__flatbuffer_generated_f64__
  }

  def generate(%Schema{} = schema) do
    reachable = CodegenSchema.reachable(schema)

    entity_clauses =
      Enum.flat_map(schema.entities, fn {name, entity} ->
        if MapSet.member?(reachable.entity_names, name) do
          case entity do
            {:table, %{fields: fields}} -> [table_clause(name, fields, schema)]
            {:struct, %{layout: layout}} -> [struct_clause(name, layout)]
            {:enum, %{members: members, type: type}} -> [enum_clause(name, members, type)]
            _entity -> []
          end
        else
          []
        end
      end)

    scalar_types = Enum.filter(@scalar_types, &reachable_type?(reachable, &1))
    scalar_clauses = Enum.map(scalar_types, &scalar_clause/1)

    string_clauses =
      if reachable_type?(reachable, :string), do: [string_clause()], else: []

    vector_types =
      reachable.types
      |> Enum.flat_map(fn
        {:vector, type} -> [type]
        _type -> []
      end)
      |> Enum.sort()

    supported_vector_types = Enum.reject(vector_types, &match?({:union, _options}, &1))
    vector_clauses = Enum.map(vector_types, &vector_clause(&1, schema))

    decoders =
      scalar_types
      |> Enum.map(&Map.fetch!(@decoder_by_scalar, &1))
      |> then(&[:i32, :u16, :u32 | &1])
      |> then(fn decoders ->
        if Enum.any?(reachable.types, &match?({:union_type, _name}, &1)) do
          [:u8 | decoders]
        else
          decoders
        end
      end)
      |> MapSet.new()

    decoder_clauses =
      for decoder <- @decoder_types, MapSet.member?(decoders, decoder) do
        decoder_clause(decoder)
      end

    vector_reader_clauses =
      if supported_vector_types == [] do
        []
      else
        [
          quote do
            defp __flatbuffer_generated_read_vector__(_type, _binary, _offset, 0, _size),
              do: []

            defp __flatbuffer_generated_read_vector__(type, binary, offset, count, size) do
              [
                __flatbuffer_generated_read_type__(type, binary, offset)
                | __flatbuffer_generated_read_vector__(
                    type,
                    binary,
                    offset + size,
                    count - 1,
                    size
                  )
              ]
            end
          end
        ]
      end

    root_type = Macro.escape(schema.root_type)
    id_check = id_check(schema.id, root_type)

    quote do
      defp __flatbuffer_generated_read__(buffer) when is_binary(buffer) do
        unquote(id_check)
      end

      defp __flatbuffer_generated_read__(buffer), do: Flatbuffer.read(buffer, schema())

      defp __flatbuffer_generated_read_bang__(buffer) do
        buffer
        |> __flatbuffer_generated_read__()
        |> Flatbuffer.Codegen.Reader.unwrap_read!()
      end

      unquote_splicing(scalar_clauses)
      unquote_splicing(string_clauses)
      unquote_splicing(vector_clauses)

      # These deliberately form an inference boundary between generated table
      # clauses. Direct Map.put/3 calls make the compiler accumulate every
      # possible partial map shape across a wide schema.
      defp __flatbuffer_generated_put__(row, key, value), do: Map.put(row, key, value)
      defp __flatbuffer_generated_get__(row, key), do: Map.get(row, key)

      unquote_splicing(entity_clauses)
      unquote_splicing(vector_reader_clauses)
      unquote_splicing(decoder_clauses)
    end
  end

  @doc false
  @spec unwrap_read!({:ok, value} | {:error, term()}) :: value when value: term()
  def unwrap_read!({:ok, value}), do: value

  def unwrap_read!({:error, reason}) do
    raise Flatbuffer.BadFlatbufferError,
      message: "Failed to read Flatbuffer: #{inspect(reason)}"
  end

  defp reachable_type?(reachable, kind) do
    Enum.any?(reachable.types, fn
      {^kind, _options} -> true
      _type -> false
    end)
  end

  defp scalar_clause(type) do
    decoder = Map.fetch!(@decoder_by_scalar, type)

    value =
      {Map.fetch!(@decoder_function, decoder), [],
       [Macro.var(:binary, __MODULE__), Macro.var(:offset, __MODULE__)]}

    value = if type == :bool, do: quote(do: unquote(value) != 0), else: value

    quote do
      defp __flatbuffer_generated_read_type__(
             {unquote(type), _options},
             binary,
             offset
           ),
           do: unquote(value)
    end
  end

  defp string_clause do
    quote do
      defp __flatbuffer_generated_read_type__({:string, _options}, binary, offset) do
        string = offset + __flatbuffer_generated_u32__(binary, offset)
        binary_part(binary, string + 4, __flatbuffer_generated_u32__(binary, string))
      end
    end
  end

  defp vector_clause({:union, _options} = type, _schema) do
    escaped_type = Macro.escape(type)

    quote do
      defp __flatbuffer_generated_read_type__(
             {:vector, unquote(escaped_type)},
             binary,
             offset
           ) do
        vector = offset + __flatbuffer_generated_u32__(binary, offset)

        case __flatbuffer_generated_u32__(binary, vector) do
          0 -> []
          _count -> throw({:error, {:unknown_type, unquote(escaped_type)}})
        end
      end
    end
  end

  defp vector_clause(type, schema) do
    escaped_type = Macro.escape(type)
    size = Flatbuffer.Utils.sizeof(type, schema)

    quote do
      defp __flatbuffer_generated_read_type__(
             {:vector, unquote(escaped_type)},
             binary,
             offset
           ) do
        vector = offset + __flatbuffer_generated_u32__(binary, offset)
        count = __flatbuffer_generated_u32__(binary, vector)

        __flatbuffer_generated_read_vector__(
          unquote(escaped_type),
          binary,
          vector + 4,
          count,
          unquote(size)
        )
      end
    end
  end

  defp decoder_clause(:i8) do
    quote do
      defp __flatbuffer_generated_i8__(binary, offset) do
        <<_::binary-size(^offset), value::signed-8, _::binary>> = binary
        value
      end
    end
  end

  defp decoder_clause(:u8) do
    quote do
      defp __flatbuffer_generated_u8__(binary, offset) do
        <<_::binary-size(^offset), value::unsigned-8, _::binary>> = binary
        value
      end
    end
  end

  defp decoder_clause(:i16) do
    quote do
      defp __flatbuffer_generated_i16__(binary, offset) do
        <<_::binary-size(^offset), value::signed-little-16, _::binary>> = binary
        value
      end
    end
  end

  defp decoder_clause(:u16) do
    quote do
      defp __flatbuffer_generated_u16__(binary, offset) do
        <<_::binary-size(^offset), value::unsigned-little-16, _::binary>> = binary
        value
      end
    end
  end

  defp decoder_clause(:i32) do
    quote do
      defp __flatbuffer_generated_i32__(binary, offset) do
        <<_::binary-size(^offset), value::signed-little-32, _::binary>> = binary
        value
      end
    end
  end

  defp decoder_clause(:u32) do
    quote do
      defp __flatbuffer_generated_u32__(binary, offset) do
        <<_::binary-size(^offset), value::unsigned-little-32, _::binary>> = binary
        value
      end
    end
  end

  defp decoder_clause(:i64) do
    quote do
      defp __flatbuffer_generated_i64__(binary, offset) do
        <<_::binary-size(^offset), value::signed-little-64, _::binary>> = binary
        value
      end
    end
  end

  defp decoder_clause(:u64) do
    quote do
      defp __flatbuffer_generated_u64__(binary, offset) do
        <<_::binary-size(^offset), value::unsigned-little-64, _::binary>> = binary
        value
      end
    end
  end

  defp decoder_clause(:f32) do
    quote do
      defp __flatbuffer_generated_f32__(binary, offset) do
        <<_::binary-size(^offset), value::float-little-32, _::binary>> = binary
        value
      end
    end
  end

  defp decoder_clause(:f64) do
    quote do
      defp __flatbuffer_generated_f64__(binary, offset) do
        <<_::binary-size(^offset), value::float-little-64, _::binary>> = binary
        value
      end
    end
  end

  defp id_check(nil, root_type) do
    quote do
      {:ok, __flatbuffer_generated_read_type__(unquote(root_type), buffer, 0)}
    end
  end

  defp id_check(id, root_type) do
    quote do
      case binary_part(buffer, 4, 4) do
        unquote(id) ->
          {:ok, __flatbuffer_generated_read_type__(unquote(root_type), buffer, 0)}

        data_id ->
          {:error, {:id_mismatch, %{data: data_id, schema: unquote(id)}}}
      end
    end
  end

  defp table_clause(name, fields, schema) do
    field_reads =
      fields
      |> Tuple.to_list()
      |> Enum.with_index()
      |> Enum.map(fn {{field_name, type}, id} -> field_read(id, field_name, type, schema) end)

    quote do
      defp __flatbuffer_generated_read_type__(
             {:table, %{name: unquote(name)}},
             binary,
             offset
           ) do
        table = offset + __flatbuffer_generated_u32__(binary, offset)
        vtable = table - __flatbuffer_generated_i32__(binary, table)
        vtable_size = __flatbuffer_generated_u16__(binary, vtable)
        row = %{}
        unquote_splicing(field_reads)
        row
      end
    end
  end

  defp field_read(id, field_name, {:union_type, union_name}, schema) do
    {:union, %{members: members}} = Map.fetch!(schema.entities, union_name)

    cases =
      members
      |> Enum.filter(fn {index, table_name} -> is_integer(index) and is_binary(table_name) end)
      |> Enum.sort()
      |> Enum.map(fn {index, table_name} ->
        quote do
          unquote(index + 1) ->
            __flatbuffer_generated_put__(row, unquote(field_name), unquote(table_name))
        end
      end)

    entry = 4 + id * 2

    tag_case =
      case_ast(
        quote(do: __flatbuffer_generated_u8__(binary, table + data_offset)),
        cases,
        quote(do: (_unknown -> row))
      )

    quote do
      row =
        if unquote(entry) < vtable_size do
          case __flatbuffer_generated_u16__(binary, vtable + unquote(entry)) do
            0 ->
              row

            data_offset ->
              unquote(tag_case)
          end
        else
          row
        end
    end
  end

  defp field_read(
         id,
         field_name,
         {:union, %{name: union_name, type_key: type_key}},
         schema
       ) do
    {:union, %{members: members}} = Map.fetch!(schema.entities, union_name)

    cases =
      members
      |> Enum.filter(fn {index, table_name} -> is_integer(index) and is_binary(table_name) end)
      |> Enum.sort()
      |> Enum.map(fn {_index, table_name} ->
        table_type = Macro.escape({:table, %{name: table_name}})

        quote do
          unquote(table_name) ->
            __flatbuffer_generated_put__(
              row,
              unquote(field_name),
              __flatbuffer_generated_read_type__(
                unquote(table_type),
                binary,
                table + data_offset
              )
            )
        end
      end)

    entry = 4 + id * 2

    union_case =
      case_ast(
        quote(do: __flatbuffer_generated_get__(row, unquote(type_key))),
        cases,
        quote(do: (_unknown -> row))
      )

    quote do
      row =
        if unquote(entry) < vtable_size do
          case __flatbuffer_generated_u16__(binary, vtable + unquote(entry)) do
            0 ->
              row

            data_offset ->
              unquote(union_case)
          end
        else
          row
        end
    end
  end

  defp field_read(id, field_name, type, _schema) do
    entry = 4 + id * 2
    escaped_type = Macro.escape(type)

    absent =
      case type do
        {_type, %{default: default}} ->
          quote do:
                  __flatbuffer_generated_put__(
                    row,
                    unquote(field_name),
                    unquote(Macro.escape(default))
                  )

        _type ->
          quote do: row
      end

    quote do
      row =
        if unquote(entry) < vtable_size do
          case __flatbuffer_generated_u16__(binary, vtable + unquote(entry)) do
            0 ->
              unquote(absent)

            data_offset ->
              __flatbuffer_generated_put__(
                row,
                unquote(field_name),
                __flatbuffer_generated_read_type__(
                  unquote(escaped_type),
                  binary,
                  table + data_offset
                )
              )
          end
        else
          row
        end
    end
  end

  defp struct_clause(name, layout) do
    fields =
      Enum.map(layout, fn {field_name, type, offset} ->
        value =
          quote do
            __flatbuffer_generated_read_type__(
              unquote(Macro.escape(type)),
              binary,
              base_offset + unquote(offset)
            )
          end

        {Macro.escape(field_name), value}
      end)

    struct = {:%{}, [], fields}

    quote do
      defp __flatbuffer_generated_read_type__(
             {:struct, %{name: unquote(name)}},
             binary,
             base_offset
           ) do
        unquote(struct)
      end
    end
  end

  defp enum_clause(name, members, type) do
    cases =
      members
      |> Enum.filter(fn {index, member_name} ->
        is_integer(index) and not is_integer(member_name)
      end)
      |> Enum.sort()
      |> Enum.map(fn {index, member_name} ->
        quote do
          unquote(index) -> unquote(member_name)
        end
      end)

    enum_case =
      case_ast(
        quote(do: index),
        cases,
        quote(
          do: (_unknown ->
                 throw({:error, {:not_in_enum, index, unquote(Macro.escape(members))}}))
        )
      )

    quote do
      defp __flatbuffer_generated_read_type__(
             {:enum, %{name: unquote(name)}},
             binary,
             offset
           ) do
        index =
          __flatbuffer_generated_read_type__(unquote(Macro.escape(type)), binary, offset)

        unquote(enum_case)
      end
    end
  end

  defp case_ast(subject, clauses, fallback) do
    {:case, [], [subject, [do: Enum.concat(clauses ++ [fallback])]]}
  end
end
