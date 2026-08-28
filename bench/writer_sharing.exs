alias Flatbuffer.Schema

row_count =
  System.get_env("BENCH_ROWS", "500")
  |> String.to_integer()

schema_source = """
table Row {
  id: int;
  rank: long;
  enabled: bool;
  name: string (shared);
  group: string (shared);
}

table Root {
  rows: [Row];
}

root_type Root;
"""

{:ok, schema} = Schema.from_string(schema_source)

repeated = %{
  rows:
    for id <- 1..row_count do
      %{id: id, rank: id * 10, enabled: true, name: "shared-name", group: "shared-group"}
    end
}

unique = %{
  rows:
    for id <- 1..row_count do
      %{id: id, rank: id * 10, enabled: true, name: "name-#{id}", group: "group-#{id}"}
    end
}

for {name, data} <- [{"repeated", repeated}, {"unique", unique}] do
  size = data |> Flatbuffer.to_binary(schema) |> byte_size()
  IO.puts("#{name}_bytes=#{size}")
end

Benchee.run(
  %{
    "repeated strings" => fn -> Flatbuffer.to_binary(repeated, schema) end,
    "unique strings" => fn -> Flatbuffer.to_binary(unique, schema) end
  },
  warmup: System.get_env("BENCH_WARMUP", "1") |> String.to_integer(),
  time: System.get_env("BENCH_TIME", "3") |> String.to_integer(),
  memory_time: System.get_env("BENCH_MEMORY_TIME", "1") |> String.to_integer(),
  reduction_time: 0,
  print: [fast_warning: false]
)
