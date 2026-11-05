defmodule Grana.Workers.StatementUploadWorker do
  @moduledoc """
  Processa um extrato ou fatura (CSV/PDF) enviado pela tela de importação: um job por
  arquivo, enfileirado por `Grana.Imports.enqueue/4`.
  """
  use Oban.Worker, queue: :uploads, max_attempts: 1

  alias Grana.Banking.StatementProcessor
  alias Grana.Imports

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "bank" => bank,
            "statement_type" => statement_type,
            "user_id" => user_id,
            "filename" => filename
          }
        } = job
      ) do
    Imports.run(
      job,
      &StatementProcessor.process(&1, bank, statement_type, user_id, filename, job.args["model"])
    )
  end
end
