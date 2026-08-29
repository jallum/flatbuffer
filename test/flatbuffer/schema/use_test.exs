defmodule Flatbuffer.Schema.UseTest do
  use ExUnit.Case

  defmodule TestSchema do
    use Flatbuffer,
      path: "test/examples",
      file: "test_schema.fbs"
  end

  defmodule SafeTestSchema do
    use Flatbuffer,
      path: "test/examples",
      file: "test_schema.fbs",
      safe: true
  end

  defmodule NoPathTestSchema do
    use Flatbuffer,
      file: "test/examples/test_schema.fbs"
  end

  describe "When using a schema to build a module" do
    test "it will build the schema correctly" do
      assert %Flatbuffer.Schema{
               entities: %{
                 "test.Table" =>
                   {:table,
                    %{
                      fields: {{:foo, {:int, %{default: 0}}}},
                      field_ids: %{"foo" => 0}
                    }}
               },
               id: nil,
               root_type: {:table, %{name: "test.Table"}}
             } == TestSchema.schema()
    end

    test "it will encode and decode a map correctly" do
      legacy_binary =
        "0E00000000000000060008000400060000000C000000"
        |> Base.decode16!()

      encoded = TestSchema.to_binary(%{foo: 12})

      assert {:ok, %{foo: 12}} == TestSchema.read(encoded)
      assert {:ok, %{foo: 12}} == TestSchema.read(legacy_binary)
      assert {:ok, %{"foo" => 12}} == SafeTestSchema.read(legacy_binary)
      assert SafeTestSchema.schema().safe
    end

    test "it will pick out a value correctly" do
      binary_value =
        "0E00000000000000060008000400060000000C000000"
        |> Base.decode16!()

      assert 12 = TestSchema.get(binary_value, "foo")
    end

    test "it resolves the schema file relative to the cwd when no :path is given" do
      assert TestSchema.schema() == NoPathTestSchema.schema()
    end

    test "it raises at compile time when the schema file cannot be loaded" do
      assert_raise RuntimeError, ~r/Failed to load schema from file/, fn ->
        defmodule MissingFileSchema do
          use Flatbuffer, file: "does_not_exist.fbs"
        end
      end
    end
  end
end
