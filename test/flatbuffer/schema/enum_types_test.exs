defmodule Flatbuffer.Schema.EnumTypesTest do
  use ExUnit.Case,
    async: true

  use ExUnit.Case,
    parameterize: [
      %{type: :byte},
      %{type: :ubyte},
      %{type: :short},
      %{type: :ushort},
      %{type: :int},
      %{type: :uint},
      %{type: :long},
      %{type: :ulong}
    ]

  alias Flatbuffer.Schema

  describe "Schema.from_string/1" do
    test "resolves explicit and aliased enum values in both key modes", %{type: type} do
      schema = """
      enum E: #{type} { A = 0, B = 2, C = B, D }
      table Root { value: E; }
      root_type Root;
      """

      assert {:ok, %Schema{entities: %{"E" => {:enum, %{members: default_members}}}}} =
               Schema.from_string(schema)

      assert default_members == %{
               "A" => 0,
               "B" => 2,
               "C" => 2,
               "D" => 3,
               0 => :A,
               2 => :C,
               3 => :D
             }

      assert {:ok, %Schema{entities: %{"E" => {:enum, %{members: safe_members}}}}} =
               Schema.from_string(schema, safe: true)

      assert safe_members == %{
               "A" => 0,
               "B" => 2,
               "C" => 2,
               "D" => 3,
               0 => "A",
               2 => "C",
               3 => "D"
             }
    end

    test "when given a schema with an enum it will return the correct result",
         %{type: type} do
      expected_enum_name = RandomIdentifier.generate()

      expected_name_1 = RandomIdentifier.generate()
      expected_name_2 = RandomIdentifier.generate()
      expected_name_3 = RandomIdentifier.generate()
      expected_atom_1 = String.to_atom(expected_name_1)
      expected_atom_2 = String.to_atom(expected_name_2)
      expected_atom_3 = String.to_atom(expected_name_3)

      expected_table_name = RandomIdentifier.generate()

      schema = """
      enum #{expected_enum_name}: #{type} {
        #{expected_name_1},
        #{expected_name_2},
        #{expected_name_3}
      }

      table #{expected_table_name} {
        v: #{expected_enum_name};
      }

      root_type #{expected_table_name};
      """

      assert {:ok,
              %Schema{
                entities: %{
                  ^expected_enum_name =>
                    {:enum,
                     %{
                       type: {^type, %{default: 0}},
                       members: %{
                         0 => ^expected_atom_1,
                         1 => ^expected_atom_2,
                         2 => ^expected_atom_3,
                         ^expected_name_3 => 2,
                         ^expected_name_2 => 1,
                         ^expected_name_1 => 0
                       }
                     }},
                  ^expected_table_name =>
                    {:table,
                     %{
                       fields: {{:v, {:enum, %{name: ^expected_enum_name}}}},
                       field_ids: %{"v" => 0}
                     }}
                },
                root_type: {:table, %{name: ^expected_table_name}},
                id: nil
              }} = Schema.from_string(schema)
    end
  end
end
