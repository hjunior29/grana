defmodule Grana.Agents.ToolSchemasTest do
  use ExUnit.Case, async: true

  alias Grana.Agents.Analyst
  alias Grana.Agents.ChatTools
  alias Grana.Agents.SearchBuilder
  alias LangChain.ChatModels.ChatGoogleAI

  defp chat_tools,
    do:
      ChatTools.all(%{user_id: 1}) ++
        [Analyst.tool(%{user_id: 1}), SearchBuilder.tool(%{user_id: 1})]

  # Gemini only takes `enum` on string parameters and rejects the whole request otherwise.
  test "every tool the chat sends is accepted by Gemini's schema rules" do
    for tool <- chat_tools() do
      declaration = tool |> ChatGoogleAI.for_api() |> Jason.encode!() |> Jason.decode!()
      properties = get_in(declaration, ["parameters", "properties"]) || %{}

      assert properties != %{} or tool.name in ["get_data_overview", "get_installments"]

      for {name, property} <- properties,
          Map.has_key?(property, "enum") do
        assert property["type"] in ["string", "STRING"],
               "#{tool.name}.#{name} has an enum on a #{property["type"]} parameter"

        assert Enum.all?(property["enum"], &is_binary/1)
      end
    end
  end

  test "tool names are unique" do
    names = Enum.map(chat_tools(), & &1.name)
    assert names == Enum.uniq(names)
  end
end
