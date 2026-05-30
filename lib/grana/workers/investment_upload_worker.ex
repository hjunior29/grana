defmodule Grana.Workers.InvestmentUploadWorker do
  @moduledoc """
  Oban worker for processing investment statement uploads (B3/GCB).
  """
  use Oban.Worker, queue: :uploads, max_attempts: 1

  require Logger
  alias Grana.Investments

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{
          "files" => files,
          "institution_slug" => institution_slug,
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

        result =
          case Base.decode64(content_b64) do
            {:ok, content} ->
              try do
                case Investments.StatementProcessor.process(
                       content,
                       institution_slug,
                       user_id,
                       filename
                     ) do
                  {:ok, r} -> {:ok, filename, r.transaction_count, Map.get(r, :warnings, [])}
                  {:error, reason} -> {:error, filename, reason}
                end
              rescue
                e ->
                  Logger.error(
                    "Falha ao processar investimentos #{filename}: #{Exception.message(e)}\n" <>
                      Exception.format_stacktrace(__STACKTRACE__)
                  )

                  {:error, filename, "Não foi possível processar este arquivo"}
              end

            :error ->
              {:error, filename, "Arquivo com codificação inválida"}
          end

        Phoenix.PubSub.broadcast(Grana.PubSub, topic, {:file_done, index, total})
        result
      end)

    meta_results =
      Enum.map(results, fn
        {:ok, filename, count, warnings} ->
          %{"status" => "ok", "filename" => filename, "count" => count, "warnings" => warnings}

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
