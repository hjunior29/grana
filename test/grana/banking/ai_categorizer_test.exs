defmodule Grana.Banking.AICategorizerTest do
  use Grana.DataCase, async: false

  use Mimic

  import Grana.AccountsFixtures

  alias Grana.Banking.AICategorizer
  alias Grana.Accounts

  defp ai_response(text) do
    %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text}]}}]}
  end

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "categorize_batch/3" do
    test "returns error when user has no API key", %{user: user} do
      assert {:error, :no_api_key} = AICategorizer.categorize_batch(["PADARIA"], [], user.id)
    end

    test "returns mapped category ids on successful AI response", %{user: user} do
      {:ok, _} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})

      categories = [
        %{id: 1, name: "Alimentação"},
        %{id: 2, name: "Transporte"}
      ]

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:ok, ai_response(~s(["Alimentação", "Transporte"]))}
      end)

      stub(Grana.AI.Provider, :extract_text, fn body ->
        get_in(body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        |> to_string()
      end)

      assert {:ok, [1, 2]} =
               AICategorizer.categorize_batch(["PADARIA", "ONIBUS"], categories, user.id)
    end

    test "returns category_id nil for unknown category names", %{user: user} do
      {:ok, _} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})

      categories = [%{id: 1, name: "Alimentação"}]

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:ok, ai_response(~s(["Categoria Desconhecida"]))}
      end)

      stub(Grana.AI.Provider, :extract_text, fn body ->
        get_in(body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        |> to_string()
      end)

      assert {:ok, [nil]} = AICategorizer.categorize_batch(["PADARIA"], categories, user.id)
    end

    test "returns error on AI provider failure", %{user: user} do
      {:ok, _} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:error, "API Key inválida"}
      end)

      assert {:error, _reason} =
               AICategorizer.categorize_batch(
                 ["PADARIA"],
                 [%{id: 1, name: "Alimentação"}],
                 user.id
               )
    end

    test "handles JSON wrapped in markdown code block", %{user: user} do
      {:ok, _} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})

      categories = [%{id: 1, name: "Alimentação"}]
      markdown_response = "```json\n[\"Alimentação\"]\n```"

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:ok, ai_response(markdown_response)}
      end)

      stub(Grana.AI.Provider, :extract_text, fn body ->
        get_in(body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        |> to_string()
      end)

      assert {:ok, [1]} = AICategorizer.categorize_batch(["PADARIA"], categories, user.id)
    end

    test "returns error on invalid JSON response", %{user: user} do
      {:ok, _} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:ok, ai_response("not valid json at all")}
      end)

      stub(Grana.AI.Provider, :extract_text, fn body ->
        get_in(body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        |> to_string()
      end)

      assert {:error, _} =
               AICategorizer.categorize_batch(
                 ["PADARIA"],
                 [%{id: 1, name: "Alimentação"}],
                 user.id
               )
    end
  end
end
