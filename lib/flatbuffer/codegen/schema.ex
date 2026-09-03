defmodule Flatbuffer.Codegen.Schema do
  @moduledoc false

  alias Flatbuffer.Schema

  def reachable(%Schema{entities: entities, root_type: root_type}) do
    visit_types([root_type], entities, MapSet.new(), MapSet.new())
  end

  defp visit_types([], _entities, entity_names, types) do
    %{entity_names: entity_names, types: types}
  end

  defp visit_types([type | rest], entities, entity_names, types) do
    types = MapSet.put(types, type)

    case entity_name(type) do
      nil ->
        visit_types(nested_types(type) ++ rest, entities, entity_names, types)

      name ->
        if MapSet.member?(entity_names, name) do
          visit_types(rest, entities, entity_names, types)
        else
          entity = Map.fetch!(entities, name)

          visit_types(
            entity_types(entity, entities) ++ rest,
            entities,
            MapSet.put(entity_names, name),
            types
          )
        end
    end
  end

  defp entity_name({kind, %{name: name}})
       when kind in [:table, :struct, :enum, :union],
       do: name

  defp entity_name({:union_type, name}), do: name
  defp entity_name(_type), do: nil

  # Union vectors are accepted by the parser but are not supported by the
  # reader or writer. Their explicit generated error paths do not use the
  # union definition or its member tables.
  defp nested_types({:vector, {:union, _options}}), do: []
  defp nested_types({:vector, type}), do: [type]
  defp nested_types(_type), do: []

  defp entity_types({:table, %{fields: fields}}, _entities) do
    fields
    |> Tuple.to_list()
    |> Enum.map(&elem(&1, 1))
  end

  defp entity_types({:struct, %{layout: layout}}, _entities) do
    Enum.map(layout, fn {_name, type, _offset} -> type end)
  end

  defp entity_types({:enum, %{type: type}}, _entities), do: [type]

  defp entity_types({:union, %{members: members}}, entities) do
    for {index, name} <- members,
        is_integer(index),
        is_binary(name),
        Map.has_key?(entities, name),
        do: {:table, %{name: name}}
  end
end
