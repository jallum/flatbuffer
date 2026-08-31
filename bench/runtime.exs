schema_text = """
table Child {
  id: uint;
  score: double;
  label: string;
}

table Root {
  id: uint;
  enabled: bool = true;
  title: string;
  values: [int];
  children: [Child];
}

root_type Root;
"""

{:ok, schema} = Flatbuffer.Schema.from_string(schema_text)

value = %{
  id: 42,
  enabled: true,
  title: String.duplicate("flatbuffer", 8),
  values: Enum.to_list(1..100),
  children:
    Enum.map(1..20, fn id ->
      %{id: id, score: id / 3, label: "child-#{id}"}
    end)
}

buffer = Flatbuffer.to_binary(value, schema)

Benchee.run(
  %{
    "encode to binary" => fn -> Flatbuffer.to_binary(value, schema) end,
    "decode full buffer" => fn -> Flatbuffer.read!(buffer, schema) end,
    "get nested field" => fn -> Flatbuffer.get(buffer, [:children, 10, :label], schema) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  reduction_time: 1
)
