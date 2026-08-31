defmodule Flatbuffer.CursorTest do
  use ExUnit.Case, async: true

  alias Flatbuffer.Cursor

  test "reads scalar values from binary and iodata buffers" do
    cases = [
      {:get_i8, <<-12::signed-8>>, -12},
      {:get_u8, <<250::unsigned-8>>, 250},
      {:get_i16, <<-12_345::signed-little-16>>, -12_345},
      {:get_u16, <<54_321::unsigned-little-16>>, 54_321},
      {:get_i32, <<-123_456_789::signed-little-32>>, -123_456_789},
      {:get_u32, <<4_000_000_000::unsigned-little-32>>, 4_000_000_000},
      {:get_i64, <<-1_234_567_890_123::signed-little-64>>, -1_234_567_890_123},
      {:get_u64, <<12_345_678_901_234::unsigned-little-64>>, 12_345_678_901_234},
      {:get_f32, <<1.5::float-little-32>>, 1.5},
      {:get_f64, <<-2.25::float-little-64>>, -2.25}
    ]

    for {reader, encoded, expected} <- cases do
      binary = <<0, encoded::binary, 0>>
      iodata = [<<0>>, encoded, <<0>>]

      assert apply(Cursor, reader, [Cursor.wrap(binary, 1)]) == expected
      assert apply(Cursor, reader, [Cursor.wrap(iodata, 1)]) == expected
    end
  end

  test "reads byte ranges from binary and iodata buffers" do
    binary = <<0, 1, 2, 3, 4>>
    iodata = [<<0, 1>>, [<<2>>, <<3, 4>>]]

    assert Cursor.get_bytes(Cursor.wrap(binary, 1), 3) == <<1, 2, 3>>
    assert Cursor.get_bytes(Cursor.wrap(iodata, 1), 3) == <<1, 2, 3>>
  end
end
