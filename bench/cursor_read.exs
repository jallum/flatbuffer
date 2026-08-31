defmodule CursorReadBench do
  @moduledoc false

  def iodata_get_u32(data, offset) do
    data
    |> IOData.to_binary!(offset, 4)
    |> decode_u32()
  end

  def binary_part_get_u32(data, offset) do
    data
    |> binary_part(offset, 4)
    |> decode_u32()
  end

  def binary_match_get_u32(data, offset) do
    <<_::binary-size(^offset), value::unsigned-little-32, _::binary>> = data
    value
  end

  defp decode_u32(<<value::unsigned-little-32>>), do: value
end

data = :binary.copy(<<0, 1, 2, 3, 4, 5, 6, 7>>, 128)
offset = 508

Benchee.run(
  %{
    "current: IOData.to_binary!/3" => fn -> CursorReadBench.iodata_get_u32(data, offset) end,
    "alternative: binary_part/3" => fn -> CursorReadBench.binary_part_get_u32(data, offset) end,
    "alternative: binary pattern" => fn -> CursorReadBench.binary_match_get_u32(data, offset) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  reduction_time: 1
)
