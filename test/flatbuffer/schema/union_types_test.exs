defmodule FlatBuffer.Schema.UnionTypesTest do
  use ExUnit.Case
  alias Flatbuffer.Schema

  describe "union types" do
    test "union types" do
      schema = """
      file_identifier "cmnd";

      table hello
      {
        salute:string;
      }

      table bye
      {
        greeting:int;
      }
      union command { hello, bye }

      table command_root {
        data:command;
        additions_value:int;
      }

      root_type command_root;
      """

      assert {:ok,
              %Flatbuffer.Schema{
                entities: %{
                  "bye" =>
                    {:table,
                     %{
                       fields: {{:greeting, {:int, %{default: 0}}}},
                       field_ids: %{"greeting" => 0}
                     }},
                  "command" =>
                    {:union, %{members: %{0 => "hello", 1 => "bye", "bye" => 1, "hello" => 0}}},
                  "command_root" =>
                    {:table,
                     %{
                       fields: {
                         {:data_type, {:union_type, "command"}},
                         {:data, {:union, %{name: "command", type_key: :data_type}}},
                         {:additions_value, {:int, %{default: 0}}}
                       },
                       field_ids: %{"data_type" => 0, "data" => 1, "additions_value" => 2}
                     }},
                  "hello" =>
                    {:table, %{fields: {{:salute, {:string, %{}}}}, field_ids: %{"salute" => 0}}}
                },
                root_type: {:table, %{name: "command_root"}},
                id: "cmnd"
              }} == Schema.from_string(schema)
    end
  end
end
