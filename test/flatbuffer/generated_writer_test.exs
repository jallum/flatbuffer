defmodule Flatbuffer.GeneratedWriterTest do
  use ExUnit.Case, async: true

  defmodule Generated do
    use Flatbuffer, file: "test/fixtures/generated_reader.fbs"
  end

  defmodule SafeGenerated do
    use Flatbuffer,
      file: "test/fixtures/generated_reader.fbs",
      safe: true
  end

  defmodule SharingGenerated do
    use Flatbuffer, file: "test/fixtures/generated_writer.fbs"
  end

  @value %{
    enabled: true,
    count: 4_000_000_000,
    signed_byte: -100,
    unsigned_byte: 250,
    signed_short: -30_000,
    unsigned_short: 60_000,
    signed_int: -2_000_000_000,
    signed_long: -9_000_000_000,
    unsigned_long: 18_000_000_000,
    ratio: 1.5,
    score: -2.25,
    mood: :HAPPY,
    moods: [:UNKNOWN, :CURIOUS],
    title: "generated writer",
    numbers: [-2, 0, 3],
    names: ["one", "two"],
    padded: %{tag: 1, value: 72_623_859_790_382_856, code: 515},
    paddeds: [
      %{tag: 2, value: 17, code: 18},
      %{tag: 3, value: 19, code: 20}
    ],
    child: %{id: 7, label: "nested"},
    children: [%{id: 8, label: "first"}, %{id: 9, label: "second"}],
    payload_type: "generated.Other",
    payload: %{score: 3.5},
    node: %{value: 1, child: %{value: 2}}
  }

  test "matches the interpreted writer for every supported kind" do
    interpreted = Flatbuffer.to_binary(@value, Generated.schema())
    iolist = Generated.to_iolist(@value)
    generated = IO.iodata_to_binary(iolist)

    assert is_list(iolist)
    assert generated == Generated.to_binary(@value)
    assert @value == Generated.read!(iolist)
    assert Generated.read!(interpreted) == Generated.read!(generated)
  end

  test "accepts binary keys and preserves defaults" do
    value = %{"count" => 12, "mood" => "CURIOUS"}
    buffer = Generated.to_binary(value)

    assert %{count: 12, mood: :CURIOUS, enabled: true} = Generated.read!(buffer)

    assert Generated.read!(buffer) ==
             Generated.schema()
             |> then(&Flatbuffer.to_binary(value, &1))
             |> Generated.read!()
  end

  test "writes with a safe schema without changing the binary" do
    assert Generated.to_binary(@value) == SafeGenerated.to_binary(@value)
    assert %{"count" => 4_000_000_000} = SafeGenerated.read!(SafeGenerated.to_binary(@value))
  end

  test "preserves shared strings and shared vtables" do
    value = %{
      first: "same",
      second: "same",
      ordinary: "same",
      children: [%{value: 1, name: "same"}, %{value: 2, name: "same"}]
    }

    buffer = SharingGenerated.to_binary(value)
    root = root_table(buffer)
    first = buffer |> table_field(root, 0) |> then(&reference_target(buffer, &1))
    second = buffer |> table_field(root, 1) |> then(&reference_target(buffer, &1))
    ordinary = buffer |> table_field(root, 2) |> then(&reference_target(buffer, &1))
    [child_a, child_b] = table_vector_targets(buffer, root, 3)

    assert first == second
    refute first == ordinary
    assert vtable_target(buffer, child_a) == vtable_target(buffer, child_b)
    assert value == SharingGenerated.read!(buffer)
    assert buffer == Flatbuffer.to_binary(value, SharingGenerated.schema())
  end

  test "throws the same errors as the interpreted writer" do
    invalid_values = [
      %{count: "wrong"},
      %{mood: :ANGRY},
      %{child: 5},
      %{payload_type: "generated.Nope", payload: %{score: 1}},
      %{payloads: [%{score: 1}]},
      %{payloads: []}
    ]

    for value <- invalid_values do
      assert catch_throw(Generated.to_binary(value)) ==
               catch_throw(Flatbuffer.to_binary(value, Generated.schema()))
    end
  end

  test "code generation does not intern safe schema field names" do
    field_name = "generated_writer_safe_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(field_name) end

    {:ok, schema} =
      Flatbuffer.Schema.from_string(
        "table Root { #{field_name}: int; } root_type Root;",
        safe: true
      )

    assert is_tuple(Flatbuffer.Codegen.Writer.generate(schema))
    assert_raise ArgumentError, fn -> String.to_existing_atom(field_name) end
  end

  test "precomputes vector size and alignment instead of generating dispatchers" do
    {:ok, schema} =
      Flatbuffer.Schema.from_string("""
      table Child { value: int; }
      table Root { children: [Child]; }
      root_type Root;
      """)

    generated = schema |> Flatbuffer.Codegen.Writer.generate() |> Macro.to_string()

    assert generated =~ "__flatbuffer_generated_create_reference_vector__"
    refute generated =~ "__flatbuffer_generated_writer_size__"
    refute generated =~ "__flatbuffer_generated_writer_alignment__"
  end

  defp root_table(<<offset::unsigned-little-32, _rest::binary>>), do: offset

  defp vtable_target(buffer, table) do
    <<_::binary-size(^table), displacement::signed-little-32, _rest::binary>> = buffer
    table - displacement
  end

  defp table_field(buffer, table, field_id) do
    vtable = vtable_target(buffer, table)
    entry = vtable + 4 + field_id * 2
    <<_::binary-size(^entry), offset::unsigned-little-16, _rest::binary>> = buffer
    table + offset
  end

  defp reference_target(buffer, reference) do
    <<_::binary-size(^reference), offset::unsigned-little-32, _rest::binary>> = buffer
    reference + offset
  end

  defp table_vector_targets(buffer, table, field_id) do
    vector = buffer |> table_field(table, field_id) |> then(&reference_target(buffer, &1))
    <<_::binary-size(^vector), count::unsigned-little-32, _rest::binary>> = buffer

    for index <- 0..(count - 1) do
      reference = vector + 4 + index * 4
      reference_target(buffer, reference)
    end
  end
end
