defmodule Flatbuffer.FlatbufferTest do
  use ExUnit.Case
  doctest Flatbuffer

  def schema(opts \\ []) do
    """
    table Root {
      field: int;
      nested_table: Nested;
      x_or_y: X_or_Y;
    }

    table Nested {
      nested_field: int;
    }

    union X_or_Y {
      X,
      Y
    }

    table X {
      x: int;
    }

    table Y {
      y: string;
    }

    root_type Root;
    """
    |> Flatbuffer.Schema.from_string(opts)
    |> then(fn {:ok, schema} -> schema end)
  end

  def schema_with_vectors(opts \\ []) do
    """
    table Root {
      field: int;
      nested_table: Nested;
      x_or_y: X_or_Y;
      int_vector: [int];
      nested_vector: [Nested];
    }

    table Nested {
      nested_field: int;
    }

    union X_or_Y {
      X,
      Y
    }

    table X {
      x: int;
    }

    table Y {
      y: string;
    }

    root_type Root;
    """
    |> Flatbuffer.Schema.from_string(opts)
    |> then(fn {:ok, schema} -> schema end)
  end

  def fb do
    %{
      field: 1,
      nested_table: %{
        nested_field: 2
      }
    }
    |> Flatbuffer.to_binary(schema())
  end

  describe "Flatbuffer.read/2" do
    test "safe schemas decode binary field names without interning them" do
      field_name = "safe_field_#{System.unique_integer([:positive])}"
      refute_existing_atom(field_name)

      {:ok, schema} =
        Flatbuffer.Schema.from_string(
          "table Root { #{field_name}: int; } root_type Root;",
          safe: true
        )

      data = %{field_name => 7}

      assert data == data |> Flatbuffer.to_binary(schema) |> Flatbuffer.read!(schema)
      assert schema.safe
      refute_existing_atom(field_name)
    end

    test "safe mode applies to struct fields and enum values" do
      schema_text = """
      enum Mood : byte { HAPPY, SAD }
      struct Point { x: int; }
      table Root { mood: Mood = SAD; point: Point; }
      root_type Root;
      """

      {:ok, schema} = Flatbuffer.Schema.from_string(schema_text)
      {:ok, safe_schema} = Flatbuffer.Schema.from_string(schema_text, safe: true)
      data = %{"point" => %{"x" => 3}}
      buffer = Flatbuffer.to_binary(data, schema)

      assert %{mood: :SAD, point: %{x: 3}} == Flatbuffer.read!(buffer, schema)

      assert %{"mood" => "SAD", "point" => %{"x" => 3}} ==
               Flatbuffer.read!(buffer, safe_schema)
    end

    test "it will return the correct structure" do
      assert {:ok,
              %{
                field: 1,
                nested_table: %{
                  nested_field: 2
                }
              }} ==
               Flatbuffer.read(fb(), schema())
    end

    test "it will return the correct structure with a union" do
      map = %{
        field: 1,
        nested_table: %{
          nested_field: 2
        },
        x_or_y_type: "Y",
        x_or_y: %{
          y: "string"
        }
      }

      fb = Flatbuffer.to_binary(map, schema())
      assert {:ok, map} == Flatbuffer.read(fb, schema())
    end

    test "accepts a buffer whose id matches the schema's file_identifier" do
      {:ok, schema} =
        Flatbuffer.Schema.from_string("""
        table Root { field: int; }
        root_type Root;
        file_identifier "TEST";
        """)

      buffer = Flatbuffer.to_binary(%{field: 1}, schema)
      assert {:ok, %{field: 1}} == Flatbuffer.read(buffer, schema)
    end

    test "returns an id_mismatch error when the buffer id differs from the schema's" do
      {:ok, plain_schema} =
        Flatbuffer.Schema.from_string("table Root { field: int; } root_type Root;")

      {:ok, id_schema} =
        Flatbuffer.Schema.from_string("""
        table Root { field: int; }
        root_type Root;
        file_identifier "TEST";
        """)

      buffer = Flatbuffer.to_binary(%{field: 1}, plain_schema)

      assert {:error, {:id_mismatch, %{data: <<0, 0, 0, 0>>, schema: "TEST"}}} ==
               Flatbuffer.read(buffer, id_schema)

      assert_raise Flatbuffer.BadFlatbufferError, ~r/id_mismatch/, fn ->
        Flatbuffer.read!(buffer, id_schema)
      end
    end

    test "reads a buffer written with a newer schema that has extra fields" do
      {:ok, v2} =
        Flatbuffer.Schema.from_string("table Root { a: int; b: int; } root_type Root;")

      {:ok, v1} = Flatbuffer.Schema.from_string("table Root { a: int; } root_type Root;")

      buffer = Flatbuffer.to_binary(%{a: 1, b: 2}, v2)
      assert {:ok, %{a: 1}} == Flatbuffer.read(buffer, v1)
    end

    test "omits both union slots when the discriminator is zeroed" do
      map = %{field: 1, x_or_y_type: "Y", x_or_y: %{y: "string"}}
      buffer = map |> Flatbuffer.to_binary(schema()) |> replace_table_field(2, 0)

      assert {:ok, %{field: 1}} == Flatbuffer.read(buffer, schema())
    end

    test "omits both union slots when the discriminator is unknown" do
      map = %{field: 1, x_or_y_type: "Y", x_or_y: %{y: "string"}}
      buffer = map |> Flatbuffer.to_binary(schema()) |> replace_table_field(2, 255)

      assert {:ok, %{field: 1}} == Flatbuffer.read(buffer, schema())
    end

    test "omits the union value when its vtable slot is empty" do
      map = %{field: 1, x_or_y_type: "Y", x_or_y: %{y: "string"}}
      buffer = map |> Flatbuffer.to_binary(schema()) |> zero_vtable_entry(3)

      assert {:ok, %{field: 1, x_or_y_type: "Y"}} == Flatbuffer.read(buffer, schema())
    end

    test "omits an absent table field that sits before a set field" do
      map = %{field: 1, x_or_y_type: "X", x_or_y: %{x: 3}}
      buffer = Flatbuffer.to_binary(map, schema())

      assert {:ok, map} == Flatbuffer.read(buffer, schema())
    end

    test "raises BadFlatbufferError via get when an enum value is out of range" do
      {:ok, schema} =
        Flatbuffer.Schema.from_string("""
        enum Mood : byte { HAPPY, SAD }
        table Root { mood: Mood = HAPPY; }
        root_type Root;
        """)

      buffer =
        %{mood: :SAD}
        |> Flatbuffer.to_binary(schema)
        |> replace_table_field(0, 255)

      assert_raise Flatbuffer.BadFlatbufferError, ~r/not_in_enum/, fn ->
        Flatbuffer.get(buffer, :mood, schema)
      end
    end
  end

  describe "Flatbuffer.get/4" do
    test "it will return a value given a valid key or path" do
      schema = schema()
      assert 2 = Flatbuffer.get(fb(), [:nested_table, :nested_field], schema)
      assert 1 = Flatbuffer.get(fb(), :field, schema)
    end

    test "it will return nil for an invalid key or path" do
      schema = schema()
      assert nil == Flatbuffer.get(fb(), [:nested_table, :does_not_exist], schema)
      assert nil == Flatbuffer.get(fb(), :does_not_exist, schema)
    end

    test "it returns nil for an unset union" do
      schema = schema()
      assert nil == Flatbuffer.get(fb(), "x_or_y_type", schema)
      assert nil == Flatbuffer.get(fb(), "x_or_y", schema)
    end

    test "it returns nil for an unknown union discriminator" do
      schema = schema()

      buffer =
        %{"x_or_y_type" => "Y", "x_or_y" => %{"y" => "string"}}
        |> Flatbuffer.to_binary(schema)
        |> replace_table_field(2, 255)

      assert nil == Flatbuffer.get(buffer, "x_or_y_type", schema)
      assert nil == Flatbuffer.get(buffer, "x_or_y", schema)
    end

    test "it will return the correct type when given a type key for a union field" do
      schema = schema()

      fb_y =
        %{
          x_or_y_type: "Y",
          x_or_y: %{
            y: "string"
          }
        }
        |> Flatbuffer.to_binary(schema)

      assert "Y" == Flatbuffer.get(fb_y, :x_or_y_type, schema)

      fb_x =
        %{
          x_or_y_type: "X",
          x_or_y: %{
            x: 3
          }
        }
        |> Flatbuffer.to_binary(schema)

      assert "X" == Flatbuffer.get(fb_x, :x_or_y_type, schema)
    end

    test "it descends into a union value through a path" do
      schema = schema()

      fb_y =
        %{x_or_y_type: "Y", x_or_y: %{y: "string"}}
        |> Flatbuffer.to_binary(schema)

      assert "string" == Flatbuffer.get(fb_y, [:x_or_y, :y], schema)
    end

    test "it returns a vector element by index" do
      schema = schema_with_vectors()

      buffer =
        %{int_vector: [10, 20, 30], nested_vector: [%{nested_field: 7}]}
        |> Flatbuffer.to_binary(schema)

      assert 20 == Flatbuffer.get(buffer, [:int_vector, 1], schema)
      assert 7 == Flatbuffer.get(buffer, [:nested_vector, 0, :nested_field], schema)
    end

    test "it returns nil for an out-of-range vector index" do
      schema = schema_with_vectors()
      buffer = Flatbuffer.to_binary(%{int_vector: [10]}, schema)

      assert nil == Flatbuffer.get(buffer, [:int_vector, 99], schema)
    end

    test "it returns the default for a field whose vtable slot is empty" do
      schema = schema()
      buffer = Flatbuffer.to_binary(%{nested_table: %{nested_field: 2}}, schema)

      assert nil == Flatbuffer.get(buffer, :field, schema)
      assert 42 == Flatbuffer.get(buffer, :field, schema, 42)
    end
  end

  describe "Flatbuffer.fetch/4" do
    test "it will return a value given a valid key or path" do
      schema = schema()
      assert {:ok, 2} = Flatbuffer.fetch(fb(), [:nested_table, :nested_field], schema)
      assert {:ok, 1} = Flatbuffer.fetch(fb(), :field, schema)
    end

    test "it will return :error for an invalid key or path" do
      schema = schema()
      assert :error = Flatbuffer.fetch(fb(), [:nested_table, :does_not_exist], schema)
      assert :error = Flatbuffer.fetch(fb(), :does_not_exist, schema)
    end
  end

  describe "Flatbuffer.fetch!/4" do
    test "it will return a value given a valid key or path" do
      schema = schema()
      assert 2 = Flatbuffer.fetch!(fb(), [:nested_table, :nested_field], schema)
      assert 1 = Flatbuffer.fetch!(fb(), :field, schema)
    end

    test "it will return :error for an invalid key or path" do
      schema = schema()

      assert_raise KeyError, fn ->
        Flatbuffer.fetch!(fb(), [:nested_table, :does_not_exist], schema)
      end

      assert_raise KeyError, fn ->
        Flatbuffer.fetch!(fb(), :does_not_exist, schema)
      end
    end
  end

  defp replace_table_field(buffer, field_id, value) do
    <<table_offset::unsigned-little-32, _::binary>> = buffer
    <<_::binary-size(^table_offset), vtable_offset::signed-little-32, _::binary>> = buffer
    vtable_start = table_offset - vtable_offset
    field_entry = vtable_start + 4 + field_id * 2
    <<_::binary-size(^field_entry), field_offset::unsigned-little-16, _::binary>> = buffer
    value_offset = table_offset + field_offset
    <<prefix::binary-size(^value_offset), _old_value, suffix::binary>> = buffer
    prefix <> <<value>> <> suffix
  end

  defp zero_vtable_entry(buffer, field_id) do
    <<table_offset::unsigned-little-32, _::binary>> = buffer
    <<_::binary-size(^table_offset), vtable_offset::signed-little-32, _::binary>> = buffer
    vtable_start = table_offset - vtable_offset
    field_entry = vtable_start + 4 + field_id * 2
    <<prefix::binary-size(^field_entry), _entry::binary-size(2), suffix::binary>> = buffer
    prefix <> <<0, 0>> <> suffix
  end

  defp refute_existing_atom(name) do
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end
end
