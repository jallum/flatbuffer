defmodule Flatbuffer.Schema.IncludeTest do
  use ExUnit.Case
  alias Flatbuffer.Schema

  defp resolver(files) do
    fn name ->
      case Map.fetch(files, name) do
        {:ok, contents} -> {:ok, contents}
        :error -> {:error, :enoent}
      end
    end
  end

  test "resolves included files through the resolver" do
    files = %{
      "root.fbs" => """
      include "shared.fbs";

      table Root { nested: Nested; }
      root_type Root;
      """,
      "shared.fbs" => """
      table Nested { value: int; }
      """
    }

    assert {:ok, schema} = Schema.from_file("root.fbs", resolver: resolver(files))
    assert %{"Root" => _, "Nested" => _} = schema.entities

    map = %{nested: %{value: 1}}
    assert map == map |> Flatbuffer.to_binary(schema) |> Flatbuffer.read!(schema)
  end

  test "root_type may reference a type defined in an included file" do
    files = %{
      "root.fbs" => """
      include "shared.fbs";

      table Extra { flag: bool; }
      root_type Nested;
      """,
      "shared.fbs" => """
      table Nested { value: int; }
      """
    }

    assert {:ok, schema} = Schema.from_file("root.fbs", resolver: resolver(files))
    assert {:table, %{name: "Nested"}} = schema.root_type

    map = %{value: 3}
    assert map == map |> Flatbuffer.to_binary(schema) |> Flatbuffer.read!(schema)
  end

  test "tolerates circular includes" do
    files = %{
      "a.fbs" => """
      include "b.fbs";

      table A { b: B; }
      root_type A;
      """,
      "b.fbs" => """
      include "a.fbs";

      table B { value: int; }
      """
    }

    assert {:ok, schema} = Schema.from_file("a.fbs", resolver: resolver(files))

    map = %{b: %{value: 2}}
    assert map == map |> Flatbuffer.to_binary(schema) |> Flatbuffer.read!(schema)
  end

  test "returns no_resolver when a schema has includes but no resolver was given" do
    schema = """
    include "shared.fbs";

    table Root { field: int; }
    root_type Root;
    """

    assert {:error, {:no_resolver, "shared.fbs"}} == Schema.from_string(schema)
  end

  test "returns the resolver's error when an included file cannot be read" do
    schema = """
    include "missing.fbs";

    table Root { field: int; }
    root_type Root;
    """

    assert {:error, :enoent} == Schema.from_string(schema, resolver: resolver(%{}))
  end
end
