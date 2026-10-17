defmodule Grana.Imports do
  @moduledoc """
  Fila de importação de arquivos (extratos/faturas e CSVs exportados pelo Grana).

  Cada arquivo vira um job do Oban e fica guardado em disco até ser processado. O
  andamento é lido dos próprios jobs, então continua valendo fora da tela de
  importação e depois de um reinício do servidor. Quem assina `subscribe/1` recebe
  `:imports_changed` a cada arquivo que começa ou termina.
  """

  import Ecto.Query

  require Logger

  alias Grana.DataDir
  alias Grana.Repo
  alias Grana.Workers.PlatformImportWorker
  alias Grana.Workers.StatementUploadWorker

  @workers [inspect(StatementUploadWorker), inspect(PlatformImportWorker)]
  @finished_states ~w(completed discarded cancelled)

  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Grana.PubSub, topic(user_id))

  defp broadcast(user_id),
    do: Phoenix.PubSub.broadcast(Grana.PubSub, topic(user_id), :imports_changed)

  defp topic(user_id), do: "imports:#{user_id}"

  @doc "Copia um arquivo recebido para o diretório de importações e devolve o novo caminho."
  def store!(tmp_path) do
    path = Path.join(DataDir.imports_dir(), Ecto.UUID.generate())
    File.cp!(tmp_path, path)
    path
  end

  @doc """
  Enfileira um job de `worker` por arquivo (`%{filename:, path:}`), com `args` em comum.
  Se a importação anterior já terminou, o resumo dela sai da fila e esta começa do zero;
  se ainda está rodando, os arquivos entram no fim dela.
  """
  def enqueue(user_id, worker, args, files) do
    unless queue(user_id).active?, do: clear(user_id)

    files
    |> Enum.map(fn %{filename: filename, path: path} ->
      args
      |> Map.merge(%{"user_id" => user_id, "filename" => filename, "path" => path})
      |> worker.new()
    end)
    |> Oban.insert_all()

    broadcast(user_id)
  end

  @doc """
  A importação atual: os arquivos na ordem de envio, cada um com `status` (`:pending`,
  `:processing`, `:ok` ou `:error`), e os totais.
  """
  def queue(user_id) do
    files =
      user_id
      |> user_jobs()
      |> order_by(:id)
      |> Repo.all()
      |> Enum.map(&to_file/1)

    finished = Enum.count(files, &(&1.status in [:ok, :error]))

    %{
      files: files,
      total: length(files),
      finished: finished,
      failed: Enum.count(files, &(&1.status == :error)),
      transactions: files |> Enum.map(&(&1.count || 0)) |> Enum.sum(),
      active?: finished < length(files)
    }
  end

  @doc "Tira da fila os arquivos que já terminaram (o resumo some da tela)."
  def clear(user_id) do
    finished = user_jobs(user_id) |> where([j], j.state in @finished_states)

    # Um job interrompido (servidor caiu no meio) não chega a apagar o próprio arquivo.
    finished |> select([j], j.args["path"]) |> Repo.all() |> Enum.each(&File.rm/1)
    Oban.delete_all_jobs(finished)

    broadcast(user_id)
  end

  @doc """
  Corpo do job de um arquivo: lê o arquivo guardado, chama `process` com o conteúdo e
  grava o resultado no próprio job, que é de onde `queue/1` lê o andamento. O arquivo é
  apagado ao final, com sucesso ou erro.
  """
  def run(%Oban.Job{args: %{"user_id" => user_id, "path" => path}} = job, process) do
    broadcast(user_id)

    result =
      try do
        path |> File.read!() |> process.()
      rescue
        e ->
          Logger.error(
            "Falha ao importar #{job.args["filename"]}: #{inspect(e.__struct__)}\n" <>
              Exception.format_stacktrace(__STACKTRACE__)
          )

          {:error, "Não foi possível processar este arquivo"}
      after
        File.rm(path)
      end

    job
    |> Ecto.Changeset.change(meta: Map.merge(job.meta, result_meta(result)))
    |> Repo.update!()

    Grana.Cache.invalidate_user(user_id)
    broadcast(user_id)
    :ok
  end

  defp result_meta({:ok, %{transaction_count: count}}), do: %{"status" => "ok", "count" => count}

  defp result_meta({:error, reason}) when is_binary(reason) or is_atom(reason),
    do: %{"status" => "error", "error" => to_string(reason)}

  defp result_meta({:error, _reason}), do: %{"status" => "error"}

  # Jobs do formato antigo (vários arquivos num job só, sem `path`) ficam de fora.
  defp user_jobs(user_id) do
    from(j in Oban.Job,
      where: j.worker in @workers,
      where: j.args["user_id"] == ^user_id,
      where: not is_nil(j.args["path"])
    )
  end

  defp to_file(job) do
    %{
      id: job.id,
      filename: job.args["filename"],
      bank: job.args["bank"],
      status: status(job),
      count: job.meta["count"],
      error: job.meta["error"]
    }
  end

  defp status(%{meta: %{"status" => "ok"}}), do: :ok
  defp status(%{meta: %{"status" => "error"}}), do: :error
  defp status(%{state: "executing"}), do: :processing
  defp status(%{state: state}) when state in @finished_states, do: :error
  defp status(_job), do: :pending
end
