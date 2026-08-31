defmodule Flatbuffer.Bench.GeneratedSchema do
  use Flatbuffer, file: "bench/fixtures/runtime.fbs"
end

schema = Flatbuffer.Bench.GeneratedSchema.schema()

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
    "decode full buffer (interpreted)" => fn -> Flatbuffer.read!(buffer, schema) end,
    "decode full buffer (generated)" => fn ->
      Flatbuffer.Bench.GeneratedSchema.read!(buffer)
    end,
    "get nested field" => fn -> Flatbuffer.get(buffer, [:children, 10, :label], schema) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  reduction_time: 1
)
