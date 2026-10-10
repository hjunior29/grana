defmodule Grana.Banking.AIAnalyzerTest do
  use Grana.DataCase, async: false

  use Mimic

  import Grana.AccountsFixtures

  alias Grana.Banking.AIAnalyzer
  alias Grana.BankingFixtures

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp ai_response(json_text) do
    %{
      "candidates" => [
        %{
          "content" => %{"parts" => [%{"text" => json_text}]},
          "finishReason" => "STOP"
        }
      ]
    }
  end

  defp ai_response_with_finish(json_text, finish_reason) do
    %{
      "candidates" => [
        %{
          "content" => %{"parts" => [%{"text" => json_text}]},
          "finishReason" => finish_reason
        }
      ]
    }
  end

  defp valid_analysis_json do
    Jason.encode!(%{
      "nota" => 7.5,
      "titulo" => "Análise Financeira",
      "resumo" => "Situação financeira estável.",
      "pontos" => [
        %{"tipo" => "positivo", "texto" => "Saldo positivo no mês"},
        %{"tipo" => "dica", "texto" => "Reduza gastos variáveis"}
      ],
      "alerta" => nil,
      "resposta" => nil
    })
  end

  defp set_api_key(user), do: ai_fixture(user, %{model: "gemini-2.0-flash"})

  defp stub_provider_success(json_text \\ nil) do
    body = ai_response(json_text || valid_analysis_json())

    stub(Grana.AI.Provider, :generate_content, fn _prompt, _config -> {:ok, body} end)

    stub(Grana.AI.Provider, :extract_text, fn resp ->
      get_in(resp, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
      |> to_string()
    end)

    stub(Grana.AI.Provider, :finish_reason, fn resp ->
      get_in(resp, ["candidates", Access.at(0), "finishReason"])
    end)
  end

  # ---------------------------------------------------------------------------
  # analyze_with_filters/3
  # ---------------------------------------------------------------------------

  describe "analyze_with_filters/3 — auth" do
    test "returns :no_api_key when user has no AI key configured" do
      user = user_fixture()

      assert {:error, :no_api_key} =
               AIAnalyzer.analyze_with_filters(user.id, %{year: 2026, month: 1})
    end
  end

  describe "analyze_with_filters/3 — no transactions" do
    setup do
      user = user_fixture()
      set_api_key(user)
      %{user: user}
    end

    test "returns error when no transactions match the filters", %{user: user} do
      filters = %{year: 2026, month: 1, bank: "all", type: "all", statement_type: "all"}

      assert {:error, msg} = AIAnalyzer.analyze_with_filters(user.id, filters)
      assert is_binary(msg)
      assert msg =~ "Nenhuma transação"
    end

    test "returns error for yearly view with no transactions", %{user: user} do
      filters = %{year: 2026, month: 0, bank: "all", type: "all", statement_type: "all"}

      assert {:error, msg} = AIAnalyzer.analyze_with_filters(user.id, filters)
      assert is_binary(msg)
      assert msg =~ "Nenhuma transação"
    end
  end

  describe "analyze_with_filters/3 — monthly view" do
    setup do
      user = user_fixture()
      set_api_key(user)

      BankingFixtures.transaction_fixture(user, %{
        date: ~D[2026-01-15],
        amount: "-150.00",
        type: "debit"
      })

      %{user: user}
    end

    test "returns {:ok, map} with all required fields on success", %{user: user} do
      stub_provider_success()
      filters = %{year: 2026, month: 1, bank: "all", type: "all", statement_type: "all"}

      assert {:ok, result} = AIAnalyzer.analyze_with_filters(user.id, filters)
      assert is_map(result)
      assert Map.has_key?(result, "titulo")
      assert Map.has_key?(result, "resumo")
      assert Map.has_key?(result, "pontos")
      assert is_list(result["pontos"])
    end

    test "returns {:ok, map} with numeric nota field", %{user: user} do
      stub_provider_success()
      filters = %{year: 2026, month: 1}

      assert {:ok, result} = AIAnalyzer.analyze_with_filters(user.id, filters)
      assert is_number(result["nota"]) or is_binary(result["nota"])
    end

    test "accepts filters with string keys", %{user: user} do
      stub_provider_success()
      filters = %{"year" => 2026, "month" => 1, "bank" => "all"}

      assert {:ok, _result} = AIAnalyzer.analyze_with_filters(user.id, filters)
    end

    test "returns error when AI provider call fails", %{user: user} do
      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:error, "Limite de requisições atingido. Aguarde alguns minutos e tente novamente."}
      end)

      filters = %{year: 2026, month: 1}

      assert {:error, reason} = AIAnalyzer.analyze_with_filters(user.id, filters)
      assert is_binary(reason)
    end

    test "returns error when AI response JSON is invalid", %{user: user} do
      body = ai_response("this is not json at all <<<")

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config -> {:ok, body} end)

      stub(Grana.AI.Provider, :extract_text, fn resp ->
        get_in(resp, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        |> to_string()
      end)

      stub(Grana.AI.Provider, :finish_reason, fn resp ->
        get_in(resp, ["candidates", Access.at(0), "finishReason"])
      end)

      filters = %{year: 2026, month: 1}

      assert {:error, msg} = AIAnalyzer.analyze_with_filters(user.id, filters)
      assert is_binary(msg)
    end

    test "returns error when AI response is missing required fields", %{user: user} do
      incomplete_json = Jason.encode!(%{"nota" => 8.0, "titulo" => "Título"})
      body = ai_response(incomplete_json)

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config -> {:ok, body} end)

      stub(Grana.AI.Provider, :extract_text, fn resp ->
        get_in(resp, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        |> to_string()
      end)

      stub(Grana.AI.Provider, :finish_reason, fn resp ->
        get_in(resp, ["candidates", Access.at(0), "finishReason"])
      end)

      filters = %{year: 2026, month: 1}

      assert {:error, msg} = AIAnalyzer.analyze_with_filters(user.id, filters)
      assert is_binary(msg)
    end

    test "returns truncation error when finishReason is MAX_TOKENS", %{user: user} do
      body = ai_response_with_finish("truncated json {\"nota\": 5", "MAX_TOKENS")

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config -> {:ok, body} end)

      stub(Grana.AI.Provider, :extract_text, fn resp ->
        get_in(resp, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        |> to_string()
      end)

      stub(Grana.AI.Provider, :finish_reason, fn resp ->
        get_in(resp, ["candidates", Access.at(0), "finishReason"])
      end)

      filters = %{year: 2026, month: 1}

      assert {:error, msg} = AIAnalyzer.analyze_with_filters(user.id, filters)
      assert msg =~ "token" or msg =~ "Token" or msg =~ "limite"
    end

    test "passes custom_prompt to the analysis", %{user: user} do
      stub_provider_success()
      filters = %{year: 2026, month: 1}

      assert {:ok, _result} =
               AIAnalyzer.analyze_with_filters(user.id, filters, "Qual foi o maior gasto?")
    end
  end

  describe "analyze_with_filters/3 — yearly view" do
    setup do
      user = user_fixture()
      set_api_key(user)

      BankingFixtures.transaction_fixture(user, %{
        date: ~D[2026-03-10],
        amount: "-200.00",
        type: "debit"
      })

      BankingFixtures.transaction_fixture(user, %{
        date: ~D[2026-06-20],
        amount: "3000.00",
        type: "credit"
      })

      %{user: user}
    end

    test "returns {:ok, map} for yearly view (month: 0)", %{user: user} do
      stub_provider_success()
      filters = %{year: 2026, month: 0}

      assert {:ok, result} = AIAnalyzer.analyze_with_filters(user.id, filters)
      assert is_map(result)
      assert Map.has_key?(result, "resumo")
    end

    test "returns {:ok, map} for yearly view (month: nil)", %{user: user} do
      stub_provider_success()
      filters = %{year: 2026, month: nil}

      assert {:ok, result} = AIAnalyzer.analyze_with_filters(user.id, filters)
      assert is_map(result)
    end
  end
end
