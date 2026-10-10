defmodule Grana.Workers.FinancialAlertsWorker do
  @moduledoc """
  Resumo diário por email dos alertas do Open Finance (fatura vencendo, saldo
  negativo). Só roda com SMTP efetivo e conexões; sem alertas, não envia nada.
  `max_attempts: 1` garante no máximo um email por execução diária do cron.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 1

  require Logger

  alias Grana.Accounts
  alias Grana.Accounts.{Scope, UserNotifier}
  alias Grana.OpenFinance
  alias Grana.OpenFinance.Alerts

  @impl Oban.Worker
  def perform(_job) do
    with %{} = owner <- Accounts.get_owner(),
         true <- Accounts.smtp_configured?(),
         [_ | _] = alerts <- owner |> Scope.for_user() |> alerts() do
      case UserNotifier.deliver_financial_alerts(owner, alerts) do
        {:ok, _email} -> :ok
        {:error, reason} -> Logger.warning("FinancialAlerts: falha no envio: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp alerts(scope) do
    scope
    |> OpenFinance.list_connections()
    |> Enum.flat_map(& &1.accounts)
    |> Alerts.list()
    |> Enum.map(& &1.message)
  end
end
