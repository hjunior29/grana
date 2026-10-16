defmodule Grana.Workers.PlatformImportWorker do
  @moduledoc """
  Importa um CSV exportado pela própria plataforma (Grana): um job por arquivo,
  enfileirado por `Grana.Imports.enqueue/4`. Detecta sozinho se o arquivo é bancário
  ou de investimentos.
  """
  use Oban.Worker, queue: :uploads, max_attempts: 1

  alias Grana.Imports
  alias Grana.PlatformImport

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "filename" => filename}} = job) do
    Imports.run(job, &PlatformImport.process(&1, user_id, filename))
  end
end
