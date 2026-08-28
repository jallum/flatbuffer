defmodule Flatbuffer.Schema.NamespaceTest do
  use ExUnit.Case
  alias Flatbuffer.Schema

  describe "Schema.from_string/1" do
    test "with a declared namespace, it will return the correct result" do
      expected_table_name = RandomIdentifier.generate()
      expected_full_table_name = "foo.bar.#{expected_table_name}"

      schema = """
      namespace foo.bar;

      table #{expected_table_name} {
      }

      root_type #{expected_table_name};
      """

      assert {:ok,
              %Schema{
                entities: %{
                  ^expected_full_table_name => {:table, %{fields: {}, field_ids: %{}}}
                },
                root_type: {:table, %{name: ^expected_full_table_name}},
                id: nil
              }} = Schema.from_string(schema)
    end
  end

  test "with an implied namespace, it will return the correct result" do
    expected_table_name = RandomIdentifier.generate()
    expected_full_table_name = "foo.bar.#{expected_table_name}"

    schema = """
    table #{expected_full_table_name} {
    }

    root_type #{expected_full_table_name};
    """

    assert {:ok,
            %Schema{
              entities: %{
                ^expected_full_table_name => {:table, %{fields: {}, field_ids: %{}}}
              },
              root_type: {:table, %{name: ^expected_full_table_name}},
              id: nil
            }} = Schema.from_string(schema)
  end

  test "with an mix of declared and implied namespaces, it will return the correct result" do
    expected_table_name = RandomIdentifier.generate()
    expected_full_table_name = "foo.bar.#{expected_table_name}"

    schema = """
    namespace foo.bar;

    table #{expected_table_name} {
    }

    root_type #{expected_full_table_name};
    """

    assert {:ok,
            %Schema{
              entities: %{
                ^expected_full_table_name => {:table, %{fields: {}, field_ids: %{}}}
              },
              root_type: {:table, %{name: ^expected_full_table_name}},
              id: nil
            }} = Schema.from_string(schema)
  end

  test "with a full namespace specified, but not declared, it will return the correct error" do
    expected_table_name = RandomIdentifier.generate()
    expected_full_table_name = "foo.bar.#{expected_table_name}"

    schema = """
    table #{expected_table_name} {
    }

    root_type #{expected_full_table_name};
    """

    assert {:error, {:root_type_not_found, ^expected_full_table_name}} =
             Schema.from_string(schema)
  end
end
