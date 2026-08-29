defmodule Flatbuffer.Utils do
  @moduledoc false

  def scalar_size({type, _options}), do: scalar_size(type)
  def scalar_size(:byte), do: 1
  def scalar_size(:ubyte), do: 1
  def scalar_size(:bool), do: 1
  def scalar_size(:short), do: 2
  def scalar_size(:ushort), do: 2
  def scalar_size(:int), do: 4
  def scalar_size(:uint), do: 4
  def scalar_size(:float), do: 4
  def scalar_size(:long), do: 8
  def scalar_size(:ulong), do: 8
  def scalar_size(:double), do: 8
  def scalar_size(type), do: throw({:error, {:unknown_scalar, type}})

  def sizeof({:enum, %{name: enum_name}}, schema) do
    {:enum, %{type: type}} = Map.get(schema.entities, enum_name)
    sizeof(type, schema)
  end

  def sizeof({:struct, %{name: struct_name}}, schema) do
    {:struct, %{members: members}} = Map.get(schema.entities, struct_name)
    Enum.reduce(members, 0, fn {_, type}, acc -> acc + sizeof(type, schema) end)
  end

  def sizeof({:table, _}, _), do: 4
  def sizeof({:vector, _}, _), do: 4
  def sizeof({:union, _}, _), do: 4
  def sizeof({:string, _}, _), do: 4

  def sizeof(type, _), do: scalar_size(type)
end
