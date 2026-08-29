defmodule Flatbuffer.ScalarRoundTripTest do
  use ExUnit.Case

  def schema do
    """
    table Scalars {
      a_bool: bool;
      a_byte: byte;
      a_ubyte: ubyte;
      a_short: short;
      a_ushort: ushort;
      an_int: int;
      a_uint: uint;
      a_long: long;
      a_ulong: ulong;
      a_float: float;
      a_double: double;
      bools: [bool];
    }

    root_type Scalars;
    """
    |> Flatbuffer.Schema.from_string()
    |> then(fn {:ok, schema} -> schema end)
  end

  test "round-trips every scalar type with non-default values" do
    map = %{
      a_bool: true,
      a_byte: -100,
      a_ubyte: 200,
      a_short: -12_345,
      a_ushort: 60_000,
      an_int: -1_000_000,
      a_uint: 3_000_000_000,
      a_long: -9_000_000_000_000_000_000,
      a_ulong: 18_000_000_000_000_000_000,
      a_float: 1.5,
      a_double: 2.25,
      bools: [true, false, true]
    }

    schema = schema()
    assert map == map |> Flatbuffer.to_binary(schema) |> Flatbuffer.read!(schema)
  end

  test "round-trips a vector of enums" do
    {:ok, schema} =
      Flatbuffer.Schema.from_string("""
      enum Mood : short { HAPPY, SAD, ANGRY }
      table Root { moods: [Mood]; }
      root_type Root;
      """)

    map = %{moods: [:ANGRY, :HAPPY, :SAD]}
    assert map == map |> Flatbuffer.to_binary(schema) |> Flatbuffer.read!(schema)
  end
end
