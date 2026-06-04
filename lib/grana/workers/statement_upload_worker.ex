defmodule Grana.Workers.StatementUploadWorker do
  @moduledoc """
  Oban worker for processing banking statement uploads (CSV/PDF).
  """
  use Oban.Worker, queue: :uploads, max_attempts: 1

  require Logger
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

        result =
          case Base.decode64(content_b64) do
            {:ok, content} ->
              try do
                case StatementProcessor.process(content, bank, statement_type, user_id, filename) do
                  {:ok, r} -> {:ok, filename, r.transaction_count}
                  {:error, reason} -> {:error, filename, reason}
                end
              rescue
                e ->
                  Logger.error(
                    "Falha ao processar extrato #{filename}: #{Exception.message(e)}\n" <>
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

    # Upload altera os dados do usuário: invalida o cache de leituras (os
    # processors já invalidam por arquivo; aqui é a garantia no nível do upload).
    Grana.Cache.invalidate_user(user_id)

    Phoenix.PubSub.broadcast(Grana.PubSub, topic, {:upload_complete, results})
    :ok
  end
end
