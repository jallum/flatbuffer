defmodule Flatbuffer.Schema.TableTest do
  use ExUnit.Case
  alias Flatbuffer.Schema

  describe "Schema.from_string/1" do
    test "retains the shared attribute on string fields" do
      schema = "table Table { pooled: string (shared); plain: string; } root_type Table;"

      assert {:ok,
              %Schema{
                entities: %{
                  "Table" =>
                    {:table,
                     %{
                       fields: {
                         {:pooled, {:string, %{shared: true}}},
                         {:plain, {:string, %{}}}
                       }
                     }}
                }
              }} = Schema.from_string(schema)
    end

    test "keeps one canonical field tuple and a binary name-to-id index" do
      field_name = "field_#{System.unique_integer([:positive])}"

      assert_raise ArgumentError, fn -> String.to_existing_atom(field_name) end

      schema = """
      table Table {
        #{field_name}: int;
      }

      root_type Table;
      """

      assert {:ok,
              %Schema{
                entities: %{
                  "Table" =>
                    {:table,
                     %{
                       fields: {{^field_name, {:int, %{default: 0}}}},
                       field_ids: %{^field_name => 0}
                     }}
                }
              }} = Schema.from_string(schema, safe: true)

      assert_raise ArgumentError, fn -> String.to_existing_atom(field_name) end
    end

    test "pre-resolves approved output atoms in the default mode" do
      field_name = "field_#{System.unique_integer([:positive])}"

      schema = "table Table { #{field_name}: int; } root_type Table;"

      assert {:ok,
              %Schema{
                entities: %{
                  "Table" =>
                    {:table,
                     %{fields: {{field_atom, {:int, %{default: 0}}}}, field_ids: field_ids}}
                },
                safe: false
              }} = Schema.from_string(schema)

      assert field_atom == String.to_existing_atom(field_name)
      assert field_ids == %{field_name => 0}
    end

    test "with a single table it will return the correct result" do
      schema = """
      table Table {
      }

      root_type Table;
      """

      assert {:ok,
              %Schema{
                entities: %{"Table" => {:table, %{fields: {}, field_ids: %{}}}},
                root_type: {:table, %{name: "Table"}},
                id: nil
              }} == Schema.from_string(schema)
    end

    test "with a nested table it will return the correct result" do
      schema = """
      table Table {
        nested_table: NestedTable;
      }

      table NestedTable {
      }

      root_type Table;
      """

      assert {
               :ok,
               %Schema{
                 entities: %{
                   "Table" => {
                     :table,
                     %{
                       fields: {{:nested_table, {:table, %{name: "NestedTable"}}}},
                       field_ids: %{"nested_table" => 0}
                     }
                   },
                   "NestedTable" => {:table, %{fields: {}, field_ids: %{}}}
                 },
                 id: nil,
                 root_type: {:table, %{name: "Table"}}
               }
             } == Schema.from_string(schema)
    end

    test "with a all sorts of fields it will return the correct result" do
      schema = """
      table Table {
        byte: byte;
        ubyte: ubyte;
        short: short;
        ushort: ushort;
        int: int;
        uint: uint;
        long: long;
        ulong: ulong;
        float: float;
        double: double;

        nested_table: NestedTable;
        enum: ByteEnum;

        string: string;
        vector_of_byte: [byte];
        vector_of_ubyte: [ubyte];
        vector_of_short: [short];
        vector_of_ushort: [ushort];
        vector_of_int: [int];
        vector_of_uint: [uint];
        vector_of_long: [long];
        vector_of_ulong: [ulong];
        vector_of_float: [float];
        vector_of_double: [double];
        vector_of_string: [string];
        vector_of_nested_table: [NestedTable];
        vector_of_byte_enum: [ByteEnum];

        struct: Struct;
        vector_of_struct: [Struct];
      }

      enum ByteEnum : byte {
        A,
        B,
        C
      }

      struct Struct {
        field1: byte;
        field2: short;
      }

      table NestedTable {
      }

      root_type Table;
      """

      assert {:ok,
              %Schema{
                entities: %{
                  "NestedTable" => {:table, %{fields: {}, field_ids: %{}}},
                  "Table" =>
                    {:table,
                     %{
                       fields: {
                         {:byte, {:byte, %{default: 0}}},
                         {:ubyte, {:ubyte, %{default: 0}}},
                         {:short, {:short, %{default: 0}}},
                         {:ushort, {:ushort, %{default: 0}}},
                         {:int, {:int, %{default: 0}}},
                         {:uint, {:uint, %{default: 0}}},
                         {:long, {:long, %{default: 0}}},
                         {:ulong, {:ulong, %{default: 0}}},
                         {:float, {:float, %{default: 0}}},
                         {:double, {:double, %{default: 0}}},
                         {:nested_table, {:table, %{name: "NestedTable"}}},
                         {:enum, {:enum, %{name: "ByteEnum"}}},
                         {:string, {:string, %{}}},
                         {:vector_of_byte, {:vector, {:byte, %{default: 0}}}},
                         {:vector_of_ubyte, {:vector, {:ubyte, %{default: 0}}}},
                         {:vector_of_short, {:vector, {:short, %{default: 0}}}},
                         {:vector_of_ushort, {:vector, {:ushort, %{default: 0}}}},
                         {:vector_of_int, {:vector, {:int, %{default: 0}}}},
                         {:vector_of_uint, {:vector, {:uint, %{default: 0}}}},
                         {:vector_of_long, {:vector, {:long, %{default: 0}}}},
                         {:vector_of_ulong, {:vector, {:ulong, %{default: 0}}}},
                         {:vector_of_float, {:vector, {:float, %{default: 0}}}},
                         {:vector_of_double, {:vector, {:double, %{default: 0}}}},
                         {:vector_of_string, {:vector, {:string, %{}}}},
                         {:vector_of_nested_table, {:vector, {:table, %{name: "NestedTable"}}}},
                         {:vector_of_byte_enum, {:vector, {:enum, %{name: "ByteEnum"}}}},
                         {:struct, {:struct, %{name: "Struct"}}},
                         {:vector_of_struct, {:vector, {:struct, %{name: "Struct"}}}}
                       },
                       field_ids: %{
                         "byte" => 0,
                         "ubyte" => 1,
                         "short" => 2,
                         "ushort" => 3,
                         "int" => 4,
                         "uint" => 5,
                         "long" => 6,
                         "ulong" => 7,
                         "float" => 8,
                         "double" => 9,
                         "nested_table" => 10,
                         "enum" => 11,
                         "string" => 12,
                         "vector_of_byte" => 13,
                         "vector_of_ubyte" => 14,
                         "vector_of_short" => 15,
                         "vector_of_ushort" => 16,
                         "vector_of_int" => 17,
                         "vector_of_uint" => 18,
                         "vector_of_long" => 19,
                         "vector_of_ulong" => 20,
                         "vector_of_float" => 21,
                         "vector_of_double" => 22,
                         "vector_of_string" => 23,
                         "vector_of_nested_table" => 24,
                         "vector_of_byte_enum" => 25,
                         "struct" => 26,
                         "vector_of_struct" => 27
                       }
                     }},
                  "Struct" => {:struct, %{members: [field1: :byte, field2: :short]}},
                  "ByteEnum" =>
                    {:enum,
                     %{
                       type: {:byte, %{default: 0}},
                       members: %{
                         0 => :A,
                         1 => :B,
                         2 => :C,
                         "A" => 0,
                         "B" => 1,
                         "C" => 2
                       }
                     }}
                },
                id: nil,
                root_type: {:table, %{name: "Table"}},
                safe: false
              }} == Schema.from_string(schema)
    end
  end
end
