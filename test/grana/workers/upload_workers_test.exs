defmodule Grana.Workers.UploadWorkersTest do
  use Grana.DataCase, async: false

  alias Grana.Workers.StatementUploadWorker
  alias Grana.Workers.InvestmentUploadWorker

  import Grana.AccountsFixtures

  setup do
    user = user_fixture()
    topic = "upload:#{user.id}"
    Phoenix.PubSub.subscribe(Grana.PubSub, topic)
    %{user: user, topic: topic}
  end

  describe "StatementUploadWorker with invalid base64" do
    test "reports error for corrupted base64 content", %{user: user, topic: topic} do
      job =
        StatementUploadWorker.new(%{
          "files" => [
            %{"filename" => "bad.csv", "content_b64" => "%%%invalid-base64%%%"}
          ],
          "bank" => "nubank",
          "statement_type" => "extrato",
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = StatementUploadWorker.perform(job)
      assert result == :ok

      # Should receive upload_complete with error result
      assert_receive {:upload_complete, results}, 5_000
      assert [{:error, "bad.csv", "Arquivo com codificação inválida"}] = results
    end

    test "handles mix of valid and invalid base64 files", %{user: user, topic: topic} do
      # Valid base64 will fail at processing (no real CSV), but won't crash on decode
      valid_b64 = Base.encode64("date,description,amount\n2026-01-01,Test,-10.00")

      job =
        StatementUploadWorker.new(%{
          "files" => [
            %{"filename" => "bad.csv", "content_b64" => "not-valid-b64!!!"},
            %{"filename" => "good.csv", "content_b64" => valid_b64}
          ],
          "bank" => "nubank",
          "statement_type" => "extrato",
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = StatementUploadWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      # First file should be a decode error
      assert {:error, "bad.csv", "Arquivo com codificação inválida"} = Enum.at(results, 0)
    end
  end

  describe "InvestmentUploadWorker with invalid base64" do
    test "reports error for corrupted base64 content", %{user: user, topic: topic} do
      job =
        InvestmentUploadWorker.new(%{
          "files" => [
            %{"filename" => "bad.xlsx", "content_b64" => "%%%invalid%%%"}
          ],
          "institution_slug" => "b3",
          "user_id" => user.id,
          "topic" => topic
        })
        |> Oban.insert!()

      result = InvestmentUploadWorker.perform(job)
      assert result == :ok

      assert_receive {:upload_complete, results}, 5_000
      assert [{:error, "bad.xlsx", "Arquivo com codificação inválida"}] = results
    end
  end
end
