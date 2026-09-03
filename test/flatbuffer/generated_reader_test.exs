defmodule Flatbuffer.GeneratedReaderTest do
  use ExUnit.Case, async: true

  @schema_file Path.expand("../fixtures/generated_reader.fbs", __DIR__)

  defmodule Generated do
    use Flatbuffer,
      file: "test/fixtures/generated_reader.fbs"
  end

  defmodule SafeGenerated do
    use Flatbuffer,
      file: "test/fixtures/generated_reader.fbs",
      safe: true
  end

  defmodule UnionVectorGenerated do
    use Flatbuffer, file: "test/fixtures/union_vector.fbs"
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
    title: "generated reader",
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

  test "decodes every supported kind from a binary using generated code" do
    buffer = Generated.to_binary(@value)

    assert {:ok, @value} == Generated.read(buffer)
    assert @value == Generated.read!(buffer)
  end

  test "keeps the interpreted reader fallback for iodata" do
    buffer = Generated.to_binary(@value)
    split = div(byte_size(buffer), 2)

    iodata = [
      binary_part(buffer, 0, split),
      binary_part(buffer, split, byte_size(buffer) - split)
    ]

    assert {:ok, @value} == Generated.read(iodata)
  end

  test "generates safe binary keys and enum values" do
    buffer = Generated.to_binary(@value)

    assert Flatbuffer.read!(buffer, SafeGenerated.schema()) == SafeGenerated.read!(buffer)
    assert %{"mood" => "HAPPY", "padded" => %{"tag" => 1}} = SafeGenerated.read!(buffer)
  end

  test "preserves defaults and schema evolution behavior" do
    {:ok, old_schema} =
      Flatbuffer.Schema.from_string("""
      namespace generated;
      file_identifier "GENR";
      table Root {
        enabled: bool = true;
        count: uint;
      }
      root_type Root;
      """)

    buffer = Flatbuffer.to_binary(%{count: 12}, old_schema)

    assert {:ok, %{enabled: true, count: 12}} == Generated.read(buffer)
  end

  test "returns and raises the same identifier mismatch as the interpreted reader" do
    buffer = Generated.to_binary(@value)
    <<prefix::binary-size(4), _id::binary-size(4), rest::binary>> = buffer
    mismatched = prefix <> "NOPE" <> rest

    expected = {:error, {:id_mismatch, %{data: "NOPE", schema: "GENR"}}}
    assert expected == Generated.read(mismatched)

    assert_raise Flatbuffer.BadFlatbufferError, ~r/id_mismatch/, fn ->
      Generated.read!(mismatched)
    end
  end

  test "uses the same decoded result as the interpreted reader" do
    {:ok, schema} = Flatbuffer.Schema.from_file(@schema_file)
    buffer = Flatbuffer.to_binary(@value, schema)

    assert Flatbuffer.read(buffer, schema) == Generated.read(buffer)
  end

  test "generates readers only for types reachable from the root" do
    {:ok, schema} =
      Flatbuffer.Schema.from_string("""
      table Unreachable { unused: double; }
      table Root { count: uint; }
      root_type Root;
      """)

    functions =
      schema
      |> Flatbuffer.Codegen.Reader.generate()
      |> generated_private_functions()

    assert {:__flatbuffer_generated_u32__, 2} in functions
    refute {:__flatbuffer_generated_f64__, 2} in functions
    refute {:__flatbuffer_generated_size__, 1} in functions
    refute {:__flatbuffer_generated_read_vector__, 5} in functions
  end

  test "does not generate union members reachable only through an unsupported vector" do
    schema = UnionVectorGenerated.schema()

    generated = schema |> Flatbuffer.Codegen.Reader.generate() |> Macro.to_string()

    refute generated =~ "{:int, _options}"
    refute generated =~ ~s({:table, %{name: "Child"}})
  end

  test "throws the same error for an unknown enum value" do
    buffer = Generated.to_binary(@value)
    root = u32(buffer, 0)
    vtable = root - i32(buffer, root)
    mood = root + u16(buffer, vtable + 4 + 11 * 2)
    <<prefix::binary-size(^mood), _value::binary-size(2), suffix::binary>> = buffer
    corrupt = prefix <> <<99::signed-little-16>> <> suffix

    assert {:error, {:not_in_enum, 99, _members}} = catch_throw(Generated.read(corrupt))
  end

  test "preserves the interpreted reader error for unsupported union vectors" do
    {:ok, integer_vector_schema} =
      Flatbuffer.Schema.from_string("table Root { values: [int]; } root_type Root;")

    empty_buffer = Flatbuffer.to_binary(%{values: []}, integer_vector_schema)
    buffer = Flatbuffer.to_binary(%{values: [1]}, integer_vector_schema)

    assert UnionVectorGenerated.read(empty_buffer) ==
             Flatbuffer.read(empty_buffer, UnionVectorGenerated.schema())

    assert catch_throw(UnionVectorGenerated.read(buffer)) ==
             catch_throw(Flatbuffer.read(buffer, UnionVectorGenerated.schema()))
  end

  defp u16(binary, offset) do
    <<_::binary-size(^offset), value::unsigned-little-16, _::binary>> = binary
    value
  end

  defp u32(binary, offset) do
    <<_::binary-size(^offset), value::unsigned-little-32, _::binary>> = binary
    value
  end

  defp i32(binary, offset) do
    <<_::binary-size(^offset), value::signed-little-32, _::binary>> = binary
    value
  end

  defp generated_private_functions(ast) do
    {_ast, functions} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:defp, _metadata, [head | _body]} = node, functions ->
          {name, arguments} = definition_name_and_arguments(head)
          {node, MapSet.put(functions, {name, length(arguments || [])})}

        node, functions ->
          {node, functions}
      end)

    functions
  end

  defp definition_name_and_arguments({:when, _metadata, [head | _guards]}),
    do: definition_name_and_arguments(head)

  defp definition_name_and_arguments({name, _metadata, arguments}), do: {name, arguments}
end
