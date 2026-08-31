{:ok, schema} =
  Flatbuffer.Schema.from_string("""
  struct Point {
    x: float;
    y: float;
  }

  table Root {
    integers: [int];
    points: [Point];
  }

  root_type Root;
  """)

inputs =
  Map.new([10, 100, 1_000], fn size ->
    {"#{size} elements",
     %{
       integers: Enum.to_list(1..size),
       points: Enum.map(1..size, &%{x: &1 / 3, y: &1 / 7})
     }}
  end)

Benchee.run(
  %{
    "encode to binary" => fn value -> Flatbuffer.to_binary(value, schema) end,
    "encode to iolist" => fn value -> Flatbuffer.to_iolist(value, schema) end
  },
  inputs: inputs,
  time: 3,
  warmup: 1,
  memory_time: 1,
  reduction_time: 1
)
