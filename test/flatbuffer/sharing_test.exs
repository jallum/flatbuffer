defmodule Flatbuffer.SharingTest do
  use ExUnit.Case, async: true

  alias Flatbuffer.Schema

  describe "shared vtables" do
    test "compact vtables keep random access to trailing absent fields safe" do
      schema = schema!("table Root { present: int; absent: string; } root_type Root;")
      buffer = Flatbuffer.to_binary(%{present: 7}, schema)

      assert 7 == Flatbuffer.get(buffer, :present, schema)
      assert nil == Flatbuffer.get(buffer, :absent, schema)
    end

    test "tables with the same serialized layout reuse one vtable" do
      schema =
        schema!("""
        table Item {
          value: int;
          label: string;
        }

        table Root {
          items: [Item];
        }

        root_type Root;
        """)

      buffer =
        Flatbuffer.to_binary(
          %{items: [%{value: 1, label: "one"}, %{value: 2, label: "considerably longer"}]},
          schema
        )

      [first, second] = table_vector_targets(buffer, root_table(buffer), 0)

      assert vtable_target(buffer, first) == vtable_target(buffer, second)
      assert Enum.any?([first, second], &(vtable_displacement(buffer, &1) < 0))

      assert %{
               items: [
                 %{value: 1, label: "one"},
                 %{value: 2, label: "considerably longer"}
               ]
             } ==
               Flatbuffer.read!(buffer, schema)
    end

    test "tables with different serialized layouts keep distinct vtables" do
      schema =
        schema!("""
        table Item {
          value: int;
          label: string;
        }

        table Root {
          items: [Item];
        }

        root_type Root;
        """)

      buffer =
        Flatbuffer.to_binary(
          %{items: [%{value: 1, label: "one"}, %{value: 2}]},
          schema
        )

      [complete, partial] = table_vector_targets(buffer, root_table(buffer), 0)

      refute vtable_target(buffer, complete) == vtable_target(buffer, partial)
    end
  end

  describe "shared strings" do
    test "shared fields reuse payloads while ordinary fields remain distinct" do
      schema =
        schema!("""
        table Root {
          first: string (shared);
          second: string (shared);
          ordinary: string;
        }

        root_type Root;
        """)

      buffer =
        Flatbuffer.to_binary(%{first: "same", second: "same", ordinary: "same"}, schema)

      table = root_table(buffer)
      first = reference_target(buffer, table_field(buffer, table, 0))
      second = reference_target(buffer, table_field(buffer, table, 1))
      ordinary = reference_target(buffer, table_field(buffer, table, 2))

      assert first == second
      refute ordinary == first
      assert :binary.at(buffer, first + 4 + byte_size("same")) == 0

      assert %{first: "same", second: "same", ordinary: "same"} ==
               Flatbuffer.read!(buffer, schema)
    end

    test "the string pool is shared across nested tables" do
      schema =
        schema!("""
        table Child {
          name: string (shared);
        }

        table Root {
          left: Child;
          right: Child;
        }

        root_type Root;
        """)

      buffer = Flatbuffer.to_binary(%{left: %{name: "same"}, right: %{name: "same"}}, schema)
      root = root_table(buffer)
      left = reference_target(buffer, table_field(buffer, root, 0))
      right = reference_target(buffer, table_field(buffer, root, 1))

      left_name = reference_target(buffer, table_field(buffer, left, 0))
      right_name = reference_target(buffer, table_field(buffer, right, 0))

      assert left_name == right_name
    end
  end

  describe "reverse builder layout" do
    test "round-trips scalar, struct, enum, and vector payloads as iodata" do
      schema =
        schema!("""
        enum Mood : byte { HAPPY, SAD }

        struct Pair {
          left: int;
          right: int;
        }

        table Child {
          value: long;
          name: string (shared);
        }

        table Root {
          enabled: bool;
          count: uint;
          ratio: double;
          mood: Mood;
          pair: Pair;
          numbers: [int];
          names: [string];
          pairs: [Pair];
          children: [Child];
        }

        root_type Root;
        """)

      data = %{
        enabled: true,
        count: 4_000_000_000,
        ratio: 1.25,
        mood: :SAD,
        pair: %{left: -1, right: 2},
        numbers: [-2, 0, 3],
        names: ["one", "two"],
        pairs: [%{left: 3, right: 4}, %{left: 5, right: 6}],
        children: [%{value: 7, name: "same"}, %{value: 8, name: "same"}]
      }

      iolist = Flatbuffer.to_iolist(data, schema)

      assert is_list(iolist)
      assert data == Flatbuffer.read!(iolist, schema)
    end

    test "aligns scalar fields and referenced objects while prepending chunks" do
      schema =
        schema!("""
        table Root {
          flag: byte;
          wide: long;
          text: string (shared);
        }

        root_type Root;
        """)

      for length <- 0..7 do
        value = String.duplicate("x", length)
        buffer = Flatbuffer.to_binary(%{flag: 1, wide: 9, text: value}, schema)
        table = root_table(buffer)
        text = buffer |> table_field(table, 2) |> then(&reference_target(buffer, &1))

        assert rem(table_field(buffer, table, 1), 8) == 0
        assert rem(text, 4) == 0
        assert rem(byte_size(buffer), 8) == 0
      end
    end
  end

  defp schema!(source) do
    {:ok, schema} = Schema.from_string(source)
    schema
  end

  defp root_table(<<offset::unsigned-little-32, _::binary>>), do: offset

  defp vtable_target(buffer, table) do
    table - vtable_displacement(buffer, table)
  end

  defp vtable_displacement(buffer, table) do
    <<_::binary-size(table), offset::signed-little-32, _::binary>> = buffer
    offset
  end

  defp table_field(buffer, table, field_id) do
    vtable = vtable_target(buffer, table)
    entry = vtable + 4 + field_id * 2
    <<_::binary-size(entry), offset::unsigned-little-16, _::binary>> = buffer
    table + offset
  end

  defp reference_target(buffer, reference) do
    <<_::binary-size(reference), offset::unsigned-little-32, _::binary>> = buffer
    reference + offset
  end

  defp table_vector_targets(buffer, table, field_id) do
    vector = buffer |> table_field(table, field_id) |> then(&reference_target(buffer, &1))
    <<_::binary-size(vector), count::unsigned-little-32, _::binary>> = buffer

    for index <- 0..(count - 1) do
      reference = vector + 4 + index * 4
      reference_target(buffer, reference)
    end
  end
end
