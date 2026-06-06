defmodule Grana.Workers.PlatformImportWorker do
  @moduledoc """
  Oban worker para importar CSVs exportados pela própria plataforma (Grana).
  Detecta sozinho se cada arquivo é bancário ou de investimentos.
  """
  use Oban.Worker, queue: :uploads, max_attempts: 1

  require Logger
  alias Grana.PlatformImport

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"files" => files, "user_id" => user_id, "topic" => topic}
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
                case PlatformImport.process(content, user_id, filename) do
                  {:ok, r} -> {:ok, filename, r.transaction_count}
                  {:error, reason} -> {:error, filename, reason}
                end
              rescue
                e ->
                  Logger.error(
                    "Falha ao importar export da plataforma #{filename}: #{Exception.message(e)}\n" <>
                      Exception.format_stacktrace(__STACKTRACE__)
                  )

                  {:error, filename, "Não foi possível importar este arquivo"}
              end

            :error ->
              {:error, filename, "Arquivo com codificação inválida"}
          end

        Phoenix.PubSub.broadcast(Grana.PubSub, topic, {:file_done, index, total})
        result
      end)

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

    # Importação altera os dados do usuário: invalida o cache de leituras.
    Grana.Cache.invalidate_user(user_id)

    Phoenix.PubSub.broadcast(Grana.PubSub, topic, {:upload_complete, results})
    :ok
  end
end
