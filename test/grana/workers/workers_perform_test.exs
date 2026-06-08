defmodule Grana.Workers.WorkersPerformTest do
  use Grana.DataCase, async: false
  use Mimic

  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Accounts
  alias Grana.Banking
  alias Grana.Investments
  alias Grana.Workers.AIAnalysisWorker
  alias Grana.Workers.InactivityReminderWorker
  alias Grana.Workers.InvestmentUploadWorker
  alias Grana.Workers.PlatformImportWorker
  alias Grana.Workers.QuoteFetcher
  alias Grana.Workers.StatementUploadWorker

  # ── AIAnalysisWorker ──────────────────────────────────────────────────────────

  describe "AIAnalysisWorker.perform/1 banking" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})
      Banking.ensure_default_categories(user.id)
      transaction_fixture(user, %{description: "PADARIA", amount: "-50.00"})

      topic = "analysis:#{user.id}:#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Grana.PubSub, topic)

      valid_json =
        Jason.encode!(%{
          "titulo" => "Análise Financeira",
          "resumo" => "Situação ok",
          "pontos" => ["ponto1"],
          "nota" => 7.5
        })

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:ok,
         %{
           "candidates" => [
             %{
               "content" => %{"parts" => [%{"text" => valid_json}]},
               "finishReason" => "STOP"
             }
           ]
         }}
      end)

      stub(Grana.AI.Provider, :extract_text, fn body ->
        get_in(body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        |> to_string()
      end)

      stub(Grana.AI.Provider, :finish_reason, fn body ->
        get_in(body, ["candidates", Access.at(0), "finishReason"])
      end)

      %{user: user, topic: topic}
    end

    test "successful banking analysis broadcasts and persists", %{user: user, topic: topic} do
      job =
        AIAnalysisWorker.new(%{
          "user_id" => user.id,
          "context" => "banking",
          "filters" => %{"year" => 2026},
          "custom_prompt" => nil,
          "topic" => topic
        })
        |> Oban.insert!()

      result = AIAnalysisWorker.perform(job)
      assert result == :ok

      assert_receive {:analysis_complete, :ok}, 5_000

      analyses = Banking.list_ai_analyses(user.id)
      assert length(analyses) >= 1
    end

    test "banking analysis with all-months filter (month nil)", %{user: user, topic: topic} do
      job =
        AIAnalysisWorker.new(%{
          "user_id" => user.id,
          "context" => "banking",
          "filters" => %{"year" => 2026, "month" => nil},
          "custom_prompt" => "Onde gastei mais?",
          "topic" => topic
        })
        |> Oban.insert!()

      result = AIAnalysisWorker.perform(job)
      assert result == :ok

      assert_receive {:analysis_complete, :ok}, 5_000
    end

    test "permanent error (invalid api key) discards job", %{user: user, topic: topic} do
      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:error, "401 api_key inválida"}
      end)

      job =
        AIAnalysisWorker.new(%{
          "user_id" => user.id,
          "context" => "banking",
          "filters" => %{"year" => 2026},
          "custom_prompt" => nil,
          "topic" => topic
        })
        |> Oban.insert!()

      result = AIAnalysisWorker.perform(job)
      assert {:discard, _msg} = result

      assert_receive {:analysis_complete, {:error, _}}, 5_000
    end

    test "transient error returns error tuple", %{user: user, topic: topic} do
      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:error, "timeout connecting to server"}
      end)

      job =
        AIAnalysisWorker.new(%{
          "user_id" => user.id,
          "context" => "banking",
          "filters" => %{"year" => 2026},
          "custom_prompt" => nil,
          "topic" => topic
        })
        |> Oban.insert!()

      result = AIAnalysisWorker.perform(job)
      assert {:error, _msg} = result
    end
  end

  describe "AIAnalysisWorker.perform/1 investments" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.update_user_ai_settings(user, %{ai_api_key: "fake-key"})

      inst = Investments.ensure_b3_institution(user.id)

      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "t.csv",
          user_id: user.id,
          institution_id: inst.id
        })

      Investments.bulk_insert_transactions([
        %{
          user_id: user.id,
          statement_id: stmt.id,
          institution_id: inst.id,
          asset_name: "PETR4",
          asset_ticker: "PETR4",
          asset_type: "acao",
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        }
      ])

      topic = "analysis:#{user.id}:#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Grana.PubSub, topic)

      valid_json =
        Jason.encode!(%{
          "titulo" => "Portfolio",
          "resumo" => "Carteira saudável",
          "pontos" => ["ponto1"],
          "nota" => 8.0
        })

      stub(Grana.AI.Provider, :generate_content, fn _prompt, _config ->
        {:ok,
         %{
           "candidates" => [
             %{
               "content" => %{"parts" => [%{"text" => valid_json}]},
               "finishReason" => "STOP"
             }
           ]
         }}
      end)

      stub(Grana.AI.Provider, :extract_text, fn body ->
        get_in(body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        |> to_string()
      end)

      stub(Grana.AI.Provider, :finish_reason, fn _body -> "STOP" end)

      %{user: user, topic: topic}
    end

    test "successful investments analysis broadcasts and persists", %{user: user, topic: topic} do
      job =
        AIAnalysisWorker.new(%{
          "user_id" => user.id,
          "context" => "investments",
          "filters" => %{"year" => 2026},
          "custom_prompt" => nil,
          "topic" => topic
        })
        |> Oban.insert!()

      result = AIAnalysisWorker.perform(job)
      assert result == :ok

      assert_receive {:analysis_complete, :ok}, 5_000
    end

    test "invalid context returns error and broadcasts", %{user: user, topic: topic} do
      job =
        AIAnalysisWorker.new(%{
          "user_id" => user.id,
          "context" => "unknown_context",
          "filters" => %{},
          "custom_prompt" => nil,
          "topic" => topic
        })
        |> Oban.insert!()

      result = AIAnalysisWorker.perform(job)
      assert {:discard, _} = result

      assert_receive {:analysis_complete, {:error, _}}, 5_000
    end
  end

  # ── QuoteFetcher ──────────────────────────────────────────────────────────────

  describe "QuoteFetcher.perform/1" do
    test "returns :ok when there are no active tickers" do
      # DB is empty → no tickers → early return
      job = QuoteFetcher.new(%{}) |> Oban.insert!()
      assert :ok = QuoteFetcher.perform(job)
    end

    test "returns :ok when there are active tickers (mocked fetch)" do
      user = user_fixture()
      inst = Investments.ensure_b3_institution(user.id)

      {:ok, stmt} =
        Investments.create_statement(%{
          filename: "t.csv",
          user_id: user.id,
          institution_id: inst.id
        })

      Investments.bulk_insert_transactions([
        %{
          user_id: user.id,
          statement_id: stmt.id,
          institution_id: inst.id,
          asset_name: "PETR4",
          asset_ticker: "PETR4",
          asset_type: "acao",
          date: ~D[2026-01-15],
          operation: "compra",
          quantity: Decimal.new(10),
          unit_price: Decimal.new(30),
          total_amount: Decimal.new(300)
        }
      ])

      stub(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "results" => [
               %{
                 "symbol" => "PETR4",
                 "regularMarketPrice" => 32.5,
                 "regularMarketChangePercent" => 1.5,
                 "logourl" => nil
               }
             ]
           }
         }}
      end)

      job = QuoteFetcher.new(%{}) |> Oban.insert!()
      assert :ok = QuoteFetcher.perform(job)
    end
  end

  # ── InactivityReminderWorker ──────────────────────────────────────────────────

  describe "InactivityReminderWorker.perform/1" do
    test "returns :ok when all users are recently active" do
      user = user_fixture()

      inst = Investments.ensure_b3_institution(user.id)

      # Statement inserted NOW makes user "active" (inserted_at >= cutoff)
      {:ok, _stmt} =
        Investments.create_statement(%{
          filename: "recent.csv",
          user_id: user.id,
          institution_id: inst.id
        })

      # Stub notifier to catch any unexpected calls
      stub(Grana.Accounts.UserNotifier, :deliver_inactivity_reminder, fn _user ->
        {:ok, %{}}
      end)

      job = InactivityReminderWorker.new(%{}) |> Oban.insert!()
      assert :ok = InactivityReminderWorker.perform(job)
    end

    test "sends email to inactive confirmed user" do
      _user = user_fixture()

      expect(Grana.Accounts.UserNotifier, :deliver_inactivity_reminder, fn _user ->
        {:ok, %{}}
      end)

      job = InactivityReminderWorker.new(%{}) |> Oban.insert!()
      assert :ok = InactivityReminderWorker.perform(job)
    end

    test "handles notifier failure gracefully" do
      _user = user_fixture()

      stub(Grana.Accounts.UserNotifier, :deliver_inactivity_reminder, fn _user ->
        {:error, :timeout}
      end)

      job = InactivityReminderWorker.new(%{}) |> Oban.insert!()
      assert :ok = InactivityReminderWorker.perform(job)
    end
  end

  # ── PlatformImportWorker ──────────────────────────────────────────────────────

  describe "PlatformImportWorker.perform/1" do
    setup do
      user = user_fixture()
      topic = "platform_import:#{user.id}"
      Phoenix.PubSub.subscribe(Grana.PubSub, topic)
      %{user: user, topic: topic}
    end

    test "invalid base64 file reports error", %{user: user, topic: topic} do
      job =
        PlatformImportWorker.new(%{
          "files" => [
            %{"filename" => "export.csv", "content_b64" => "%%%invalid%%%"}
          ],
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = PlatformImportWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert [{:error, "export.csv", "Arquivo com codificação inválida"}] = results
    end

    test "valid file with successful import", %{user: user, topic: topic} do
      stub(Grana.PlatformImport, :process, fn _content, _user_id, _filename ->
        {:ok, %{transaction_count: 5}}
      end)

      content_b64 = Base.encode64("date,description,amount\n2026-01-01,Test,-10.00")

      job =
        PlatformImportWorker.new(%{
          "files" => [
            %{"filename" => "export.csv", "content_b64" => content_b64}
          ],
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = PlatformImportWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert [{:ok, "export.csv", 5}] = results
    end

    test "import error is reported as error result", %{user: user, topic: topic} do
      stub(Grana.PlatformImport, :process, fn _content, _user_id, _filename ->
        {:error, "formato inválido"}
      end)

      content_b64 = Base.encode64("invalid content")

      job =
        PlatformImportWorker.new(%{
          "files" => [
            %{"filename" => "bad.csv", "content_b64" => content_b64}
          ],
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = PlatformImportWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert [{:error, "bad.csv", _reason}] = results
    end

    test "processes multiple files", %{user: user, topic: topic} do
      stub(Grana.PlatformImport, :process, fn _content, _user_id, _filename ->
        {:ok, %{transaction_count: 3}}
      end)

      file = %{"filename" => "f.csv", "content_b64" => Base.encode64("content")}

      job =
        PlatformImportWorker.new(%{
          "files" => [file, file],
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = PlatformImportWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert length(results) == 2
    end
  end

  describe "StatementUploadWorker.perform/1" do
    setup do
      user = user_fixture()
      Grana.Banking.ensure_default_categories(user.id)
      topic = "statement_upload:#{user.id}"
      Phoenix.PubSub.subscribe(Grana.PubSub, topic)
      %{user: user, topic: topic}
    end

    test "processes valid nubank extrato CSV", %{user: user, topic: topic} do
      content = File.read!("test/support/fixtures/examples/extrato-nubank.csv")
      file = %{"filename" => "extrato.csv", "content_b64" => Base.encode64(content)}

      job =
        StatementUploadWorker.new(%{
          "files" => [file],
          "bank" => "nubank",
          "statement_type" => "extrato",
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = StatementUploadWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert [{:ok, "extrato.csv", _count}] = results
    end

    test "reports error for invalid base64", %{user: user, topic: topic} do
      file = %{"filename" => "bad.csv", "content_b64" => "not-valid-base64!!!"}

      job =
        StatementUploadWorker.new(%{
          "files" => [file],
          "bank" => "nubank",
          "statement_type" => "extrato",
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = StatementUploadWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert [{:error, "bad.csv", _reason}] = results
    end

    test "reports error for invalid CSV content", %{user: user, topic: topic} do
      file = %{"filename" => "invalid.csv", "content_b64" => Base.encode64("garbage content")}

      job =
        StatementUploadWorker.new(%{
          "files" => [file],
          "bank" => "nubank",
          "statement_type" => "extrato",
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = StatementUploadWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert [{:error, "invalid.csv", _reason}] = results
    end
  end

  describe "InvestmentUploadWorker.perform/1" do
    setup do
      user = user_fixture()
      topic = "inv_upload:#{user.id}"
      Phoenix.PubSub.subscribe(Grana.PubSub, topic)
      %{user: user, topic: topic}
    end

    test "processes valid GCB CSV", %{user: user, topic: topic} do
      content = File.read!("test/support/fixtures/examples/extrato-gcb.csv")
      file = %{"filename" => "gcb.csv", "content_b64" => Base.encode64(content)}

      job =
        InvestmentUploadWorker.new(%{
          "files" => [file],
          "institution_slug" => "gcb",
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = InvestmentUploadWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert [{:ok, "gcb.csv", _count, _warnings}] = results
    end

    test "reports error for invalid base64", %{user: user, topic: topic} do
      file = %{"filename" => "bad.csv", "content_b64" => "not-valid-base64!!!"}

      job =
        InvestmentUploadWorker.new(%{
          "files" => [file],
          "institution_slug" => "gcb",
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = InvestmentUploadWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert [{:error, "bad.csv", _reason}] = results
    end

    test "reports error for GCB with XLSX format", %{user: user, topic: topic} do
      file = %{"filename" => "wrong.xlsx", "content_b64" => Base.encode64("fake xlsx")}

      job =
        InvestmentUploadWorker.new(%{
          "files" => [file],
          "institution_slug" => "gcb",
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = InvestmentUploadWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert [{:error, "wrong.xlsx", _reason}] = results
    end

    test "processes multiple investment files", %{user: user, topic: topic} do
      content = File.read!("test/support/fixtures/examples/extrato-gcb.csv")
      file = %{"filename" => "gcb.csv", "content_b64" => Base.encode64(content)}
      file2 = %{"filename" => "gcb2.csv", "content_b64" => Base.encode64(content)}

      job =
        InvestmentUploadWorker.new(%{
          "files" => [file, file2],
          "institution_slug" => "gcb",
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = InvestmentUploadWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert length(results) == 2
    end
  end
end
