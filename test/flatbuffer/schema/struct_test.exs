defmodule Flatbuffer.Schema.StructTest do
  use ExUnit.Case
  alias Flatbuffer.Schema

  describe "Schema.from_string/1" do
    test "it parses a struct" do
      expected_field_name1 = RandomIdentifier.generate()
      expected_field_name2 = RandomIdentifier.generate()
      expected_field_name3 = RandomIdentifier.generate()
      expected_field_name4 = RandomIdentifier.generate()
      expected_field_atom1 = String.to_atom(expected_field_name1)
      expected_field_atom2 = String.to_atom(expected_field_name2)
      expected_field_atom3 = String.to_atom(expected_field_name3)
      expected_field_atom4 = String.to_atom(expected_field_name4)

      expected_struct_name = RandomIdentifier.generate()

      expected_table_name = RandomIdentifier.generate()

      struct_field_name = RandomIdentifier.generate()
      struct_field_atom = String.to_atom(struct_field_name)

      schema = """
      struct #{expected_struct_name} {
        #{expected_field_name1}: byte;
        #{expected_field_name2}: short;
        #{expected_field_name3}: int;
        #{expected_field_name4}: long;
      }

      table #{expected_table_name} {
        #{struct_field_name}: #{expected_struct_name};
      }

      root_type #{expected_table_name};
      """

      assert {:ok,
              %Schema{
                entities: %{
                  ^expected_struct_name =>
                    {:struct,
                     %{
                       members: [
                         {^expected_field_atom1, :byte},
                         {^expected_field_atom2, :short},
                         {^expected_field_atom3, :int},
                         {^expected_field_atom4, :long}
                       ]
                     }},
                  ^expected_table_name =>
                    {:table,
                     %{
                       fields: {{^struct_field_atom, {:struct, %{name: ^expected_struct_name}}}},
                       field_ids: %{^struct_field_name => 0}
                     }}
                },
                root_type: {:table, %{name: ^expected_table_name}},
                id: nil
              }} = Schema.from_string(schema)
    end
  end
end
