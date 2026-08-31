defmodule Flatbuffer.Codegen.Reader do
  @moduledoc false

  alias Flatbuffer.Schema

  def generate(%Schema{} = schema) do
    entity_clauses =
      Enum.flat_map(schema.entities, fn
        {name, {:table, %{fields: fields}}} ->
          [table_clause(name, fields, schema)]

        {name, {:struct, %{layout: layout}}} ->
          [struct_clause(name, layout)]

        {name, {:enum, %{members: members, type: type}}} ->
          [enum_clause(name, members, type)]

        _entity ->
          []
      end)

    size_clauses =
      Enum.flat_map(schema.entities, fn
        {name, {:struct, %{size: size}}} -> [size_clause(:struct, name, size)]
        {name, {:enum, %{type: type}}} -> [size_clause(:enum, name, scalar_size(type))]
        _entity -> []
      end)

    root_type = Macro.escape(schema.root_type)
    id_check = id_check(schema.id, root_type)

    quote do
      defp __flatbuffer_generated_read__(buffer) when is_binary(buffer) do
        unquote(id_check)
      end

      defp __flatbuffer_generated_read__(buffer), do: Flatbuffer.read(buffer, schema())

      defp __flatbuffer_generated_read_bang__(buffer) do
        case __flatbuffer_generated_read__(buffer) do
          {:ok, value} ->
            value

          {:error, reason} ->
            raise Flatbuffer.BadFlatbufferError,
              message: "Failed to read Flatbuffer: #{inspect(reason)}"
        end
      end

      defp __flatbuffer_generated_read_type__({:bool, _options}, binary, offset),
        do: __flatbuffer_generated_i8__(binary, offset) != 0

      defp __flatbuffer_generated_read_type__({:byte, _options}, binary, offset),
        do: __flatbuffer_generated_i8__(binary, offset)

      defp __flatbuffer_generated_read_type__({:ubyte, _options}, binary, offset),
        do: __flatbuffer_generated_u8__(binary, offset)

      defp __flatbuffer_generated_read_type__({:short, _options}, binary, offset),
        do: __flatbuffer_generated_i16__(binary, offset)

      defp __flatbuffer_generated_read_type__({:ushort, _options}, binary, offset),
        do: __flatbuffer_generated_u16__(binary, offset)

      defp __flatbuffer_generated_read_type__({:int, _options}, binary, offset),
        do: __flatbuffer_generated_i32__(binary, offset)

      defp __flatbuffer_generated_read_type__({:uint, _options}, binary, offset),
        do: __flatbuffer_generated_u32__(binary, offset)

      defp __flatbuffer_generated_read_type__({:long, _options}, binary, offset),
        do: __flatbuffer_generated_i64__(binary, offset)

      defp __flatbuffer_generated_read_type__({:ulong, _options}, binary, offset),
        do: __flatbuffer_generated_u64__(binary, offset)

      defp __flatbuffer_generated_read_type__({:float, _options}, binary, offset),
        do: __flatbuffer_generated_f32__(binary, offset)

      defp __flatbuffer_generated_read_type__({:double, _options}, binary, offset),
        do: __flatbuffer_generated_f64__(binary, offset)

      defp __flatbuffer_generated_read_type__({:string, _options}, binary, offset) do
        string = offset + __flatbuffer_generated_u32__(binary, offset)
        binary_part(binary, string + 4, __flatbuffer_generated_u32__(binary, string))
      end

      defp __flatbuffer_generated_read_type__({:vector, type}, binary, offset) do
        vector = offset + __flatbuffer_generated_u32__(binary, offset)
        count = __flatbuffer_generated_u32__(binary, vector)

        __flatbuffer_generated_read_vector__(
          type,
          binary,
          vector + 4,
          count,
          __flatbuffer_generated_size__(type)
        )
      end

      defp __flatbuffer_generated_put__(row, key, value), do: Map.put(row, key, value)
      defp __flatbuffer_generated_get__(row, key), do: Map.get(row, key)

      unquote_splicing(entity_clauses)

      defp __flatbuffer_generated_read_type__(type, _binary, _offset),
        do: throw({:error, {:unknown_type, type}})

      defp __flatbuffer_generated_read_vector__(_type, _binary, _offset, 0, _size), do: []

      defp __flatbuffer_generated_read_vector__(type, binary, offset, count, size) do
        [
          __flatbuffer_generated_read_type__(type, binary, offset)
          | __flatbuffer_generated_read_vector__(type, binary, offset + size, count - 1, size)
        ]
      end

      defp __flatbuffer_generated_size__({type, _options})
           when type in [:bool, :byte, :ubyte],
           do: 1

      defp __flatbuffer_generated_size__({type, _options}) when type in [:short, :ushort],
        do: 2

      defp __flatbuffer_generated_size__({type, _options})
           when type in [:int, :uint, :float],
           do: 4

      defp __flatbuffer_generated_size__({type, _options})
           when type in [:long, :ulong, :double],
           do: 8

      defp __flatbuffer_generated_size__({type, _options})
           when type in [:string, :vector, :table, :union],
           do: 4

      unquote_splicing(size_clauses)

      defp __flatbuffer_generated_size__(type),
        do: throw({:error, {:unknown_scalar, type}})

      defp __flatbuffer_generated_i8__(binary, offset) do
        <<_::binary-size(^offset), value::signed-8, _::binary>> = binary
        value
      end

      defp __flatbuffer_generated_u8__(binary, offset) do
        <<_::binary-size(^offset), value::unsigned-8, _::binary>> = binary
        value
      end

      defp __flatbuffer_generated_i16__(binary, offset) do
        <<_::binary-size(^offset), value::signed-little-16, _::binary>> = binary
        value
      end

      defp __flatbuffer_generated_u16__(binary, offset) do
        <<_::binary-size(^offset), value::unsigned-little-16, _::binary>> = binary
        value
      end

      defp __flatbuffer_generated_i32__(binary, offset) do
        <<_::binary-size(^offset), value::signed-little-32, _::binary>> = binary
        value
      end

      defp __flatbuffer_generated_u32__(binary, offset) do
        <<_::binary-size(^offset), value::unsigned-little-32, _::binary>> = binary
        value
      end

      defp __flatbuffer_generated_i64__(binary, offset) do
        <<_::binary-size(^offset), value::signed-little-64, _::binary>> = binary
        value
      end

      defp __flatbuffer_generated_u64__(binary, offset) do
        <<_::binary-size(^offset), value::unsigned-little-64, _::binary>> = binary
        value
      end

      defp __flatbuffer_generated_f32__(binary, offset) do
        <<_::binary-size(^offset), value::float-little-32, _::binary>> = binary
        value
      end

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

  defp size_clause(kind, name, size) do
    quote do
      defp __flatbuffer_generated_size__({unquote(kind), %{name: unquote(name)}}),
        do: unquote(size)
    end
  end

  defp scalar_size({type, _options}), do: Flatbuffer.Utils.scalar_size(type)

  defp case_ast(subject, clauses, fallback) do
    {:case, [], [subject, [do: Enum.concat(clauses ++ [fallback])]]}
  end
end
