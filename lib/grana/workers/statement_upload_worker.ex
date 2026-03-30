defmodule Grana.Workers.StatementUploadWorker do
  @moduledoc """
  Oban worker for processing banking statement uploads (CSV/PDF).
  """
  use Oban.Worker, queue: :uploads, max_attempts: 1

  alias Grana.Banking.StatementProcessor

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{
          "files" => files,
          "bank" => bank,
          "statement_type" => statement_type,
          "user_id" => user_id,
          "topic" => topic
        }
      }) do
    total = length(files)

    results =
      files
      |> Enum.with_index(1)
      |> Enum.map(fn {%{"filename" => filename, "content_b64" => content_b64}, index} ->
        Phoenix.PubSub.broadcast(Grana.PubSub, topic, {:processing_file, index, total, filename})
        content = Base.decode64!(content_b64)

        result =
          case StatementProcessor.process(content, bank, statement_type, user_id, filename) do
            {:ok, r} -> {:ok, filename, r.transaction_count}
            {:error, reason} -> {:error, filename, reason}
          end

        Phoenix.PubSub.broadcast(Grana.PubSub, topic, {:file_done, index, total})
        result
      end)

    # Serialize results for meta (tuples -> maps)
    meta_results =
      Enum.map(results, fn
        {:ok, filename, count} ->
          %{"status" => "ok", "filename" => filename, "count" => count}

        {:error, filename, reason} ->
          %{"status" => "error", "filename" => filename, "reason" => inspect(reason)}
      end)

    Oban.Job
    |> Grana.Repo.get(job_id)
    |> Ecto.Changeset.change(%{meta: %{"results" => meta_results}})
    |> Grana.Repo.update()

    Phoenix.PubSub.broadcast(Grana.PubSub, topic, {:upload_complete, results})
    :ok
  end
end
