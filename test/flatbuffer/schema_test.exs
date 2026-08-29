defmodule Flatbuffer.SchemaTest do
  use ExUnit.Case
  alias Flatbuffer.Schema

  describe "Schema.from_string/1" do
    test "when given a schema that does not declare a root type, returns the correct error" do
      schema = """
      table Table {
      }
      """

      assert {:error, :root_type_is_undefined} == Schema.from_string(schema)
    end

    test "when given a schema that declares a root type that is not a table, returns the correct error" do
      schema = """
      struct Struct {
        field1: byte;
      }

      root_type Struct;
      """

      assert {:error, {:root_type_is_not_a_table, "Struct"}} == Schema.from_string(schema)
    end

    test "when a field references an undefined type, returns the correct error" do
      schema = """
      table Root {
        x: Missing;
      }

      root_type Root;
      """

      assert {:error, {:type_not_found, "Missing"}} == Schema.from_string(schema)
    end

    test "ignores field attributes it does not recognize" do
      schema = """
      table Root {
        x: int (deprecated);
      }

      root_type Root;
      """

      assert {:ok, schema} = Schema.from_string(schema)
      assert %{x: 7} == %{x: 7} |> Flatbuffer.to_binary(schema) |> Flatbuffer.read!(schema)
    end
  end
end
