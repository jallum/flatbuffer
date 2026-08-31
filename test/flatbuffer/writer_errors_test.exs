defmodule Flatbuffer.WriterErrorsTest do
  use ExUnit.Case

  def schema do
    """
    enum Mood : byte { HAPPY, SAD }

    table Root {
      field: int;
      nested_table: Nested;
      mood: Mood = HAPPY;
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
    |> Flatbuffer.Schema.from_string()
    |> then(fn {:ok, schema} -> schema end)
  end

  test "throws wrong_type when a table field is given a non-map" do
    assert {:error, {:wrong_type, :table, 5, _path}} =
             catch_throw(Flatbuffer.to_binary(%{nested_table: 5}, schema()))
  end

  test "throws wrong_type when a scalar field is given a non-number" do
    assert {:error, {:wrong_type, :int, "nope", _path}} =
             catch_throw(Flatbuffer.to_binary(%{field: "nope"}, schema()))
  end

  test "throws wrong_type when an enum value is not a member" do
    assert {:error, {:wrong_type, :enum, "ANGRY", _path}} =
             catch_throw(Flatbuffer.to_binary(%{mood: :ANGRY}, schema()))
  end

  test "throws wrong_type when a union type is not a member" do
    assert {:error, {:wrong_type, :union, "Z", _path}} =
             catch_throw(Flatbuffer.to_binary(%{x_or_y_type: "Z", x_or_y: %{y: "s"}}, schema()))
  end

  def union_vector_schema do
    """
    table A { x: int; }
    union U { A }
    table Root { us: [U]; }
    root_type Root;
    """
    |> Flatbuffer.Schema.from_string()
    |> then(fn {:ok, schema} -> schema end)
  end

  test "throws wrong_type when writing a vector of unions" do
    assert {:error, {:wrong_type, :union, %{x: 1}, _path}} =
             catch_throw(Flatbuffer.to_binary(%{us: [%{x: 1}]}, union_vector_schema()))
  end

  test "throws unknown_scalar when writing an empty vector of unions" do
    assert {:error, {:unknown_scalar, :union}} =
             catch_throw(Flatbuffer.to_binary(%{us: []}, union_vector_schema()))
  end

  test "safe schemas skip absent fields without creating atoms" do
    field_name = "writer_safe_#{System.unique_integer([:positive])}"

    {:ok, schema} =
      Flatbuffer.Schema.from_string(
        "table Root { #{field_name}: int; other: int; } root_type Root;",
        safe: true
      )

    decoded =
      %{"other" => 1}
      |> Flatbuffer.to_binary(schema)
      |> Flatbuffer.read!(schema)

    assert %{field_name => 0, "other" => 1} == decoded
    assert_raise ArgumentError, fn -> String.to_existing_atom(field_name) end
  end
end
