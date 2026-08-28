defmodule Flatbuffer.Schema.FloatTypesTest do
  use ExUnit.Case,
    parameterize: [
      %{type: :float},
      %{type: :double}
    ]

  alias Flatbuffer.Schema

  describe "Schema.from_string/1" do
    test "when given a schema with a table containing a float field it will return the correct result",
         %{type: type} do
      expected_table_name = RandomIdentifier.generate()

      schema = """
      table #{expected_table_name} {
        v: #{type};
      }

      root_type #{expected_table_name};
      """

      assert {
               :ok,
               %Schema{
                 entities: %{
                   ^expected_table_name =>
                     {:table,
                      %{
                        fields: {{:v, {^type, %{default: 0}}}},
                        field_ids: %{"v" => 0}
                      }}
                 },
                 id: nil,
                 root_type: {:table, %{name: ^expected_table_name}}
               }
             } = Schema.from_string(schema)
    end

    test "when given a schema with a table containing a float field with an in-range, default value it will return the correct result",
         %{type: type} do
      expected_table_name = RandomIdentifier.generate()
      expected_default = random_value(type)

      schema = """
      table #{expected_table_name} {
        v: #{type} = #{Float.to_string(expected_default)};
      }

      root_type #{expected_table_name};
      """

      assert {
               :ok,
               %Schema{
                 entities: %{
                   ^expected_table_name =>
                     {:table,
                      %{
                        fields: {{:v, {^type, %{default: ^expected_default}}}},
                        field_ids: %{"v" => 0}
                      }}
                 },
                 id: nil,
                 root_type: {:table, %{name: ^expected_table_name}}
               }
             } = Schema.from_string(schema)
    end
  end

  def random_value(:float), do: do_random_f64(<<>>)
  def random_value(:double), do: do_random_f64(<<>>)

  def do_random_f32(<<f32::float-32>>), do: f32
  def do_random_f32(_), do: do_random_f32(:crypto.strong_rand_bytes(4))

  def do_random_f64(<<f64::float-64>>), do: f64
  def do_random_f64(_), do: do_random_f64(:crypto.strong_rand_bytes(8))
end
