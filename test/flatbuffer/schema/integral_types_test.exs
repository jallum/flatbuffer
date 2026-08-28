defmodule Flatbuffer.Schema.IntegralTypesTest do
  use ExUnit.Case,
    parameterize: [
      %{type: :byte, valid_range: -128..127},
      %{type: :ubyte, valid_range: 0..255},
      %{type: :short, valid_range: -32_768..32_767},
      %{type: :ushort, valid_range: 0..65_535},
      %{type: :int, valid_range: -2_147_483_648..2_147_483_647},
      %{type: :uint, valid_range: 0..4_294_967_295},
      %{type: :long, valid_range: -9_223_372_036_854_775_808..9_223_372_036_854_775_807},
      %{type: :ulong, valid_range: 0..18_446_744_073_709_551_615}
    ]

  alias Flatbuffer.Schema

  describe "Schema.from_string/1" do
    test "when given a schema with a table containing an integral field it will return the correct result",
         %{type: type} do
      schema = """
      table Table {
        v: #{type};
      }

      root_type Table;
      """

      assert {
               :ok,
               %Schema{
                 entities: %{
                   "Table" =>
                     {:table,
                      %{
                        fields: {{:v, {^type, %{default: 0}}}},
                        field_ids: %{"v" => 0}
                      }}
                 },
                 id: nil,
                 root_type: {:table, %{name: "Table"}}
               }
             } = Schema.from_string(schema)
    end

    test "when given a schema with a table containing an integral field with an in-range, decimal default value it will return the correct result",
         %{type: type, valid_range: valid_range} do
      expected_default = valid_range |> Enum.random()

      schema = """
      table Table {
        v: #{type} = #{expected_default};
      }

      root_type Table;
      """

      assert {
               :ok,
               %Schema{
                 entities: %{
                   "Table" =>
                     {:table,
                      %{
                        fields: {{:v, {^type, %{default: ^expected_default}}}},
                        field_ids: %{"v" => 0}
                      }}
                 },
                 id: nil,
                 root_type: {:table, %{name: "Table"}}
               }
             } = Schema.from_string(schema)
    end

    test "when given a schema with a table containing an integral field with an in-range, hexadecimal default value it will return the correct result",
         %{type: type, valid_range: valid_range} do
      expected_default = valid_range |> Enum.random()

      schema = """
      table Table {
        v: #{type} = #{to_hex(expected_default)};
      }

      root_type Table;
      """

      assert {:ok,
              %Schema{
                entities: %{
                  "Table" =>
                    {:table,
                     %{
                       fields: {{:v, {^type, %{default: ^expected_default}}}},
                       field_ids: %{"v" => 0}
                     }}
                },
                root_type: {:table, %{name: "Table"}},
                id: nil
              }} = Schema.from_string(schema)
    end
  end

  defp to_hex(value) when value < 0, do: "-0x#{Integer.to_string(-value, 16)}"
  defp to_hex(value), do: "0x#{Integer.to_string(value, 16)}"
end
