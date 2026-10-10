defmodule Grana.Workers.OpenFinanceSyncWorker do
  @moduledoc """
  Sincroniza conexões Open Finance (Pluggy) em background.

    * `%{"connection_id" => id}` — sincroniza uma conexão (botão, webhook, pós-conexão).
    * `%{"user_id" => id, "item_id" => item_id}` — vincula um Item criado pelo widget
      cujo `onSuccess` não chegou (avisado pelo webhook `item/created`).
    * `%{}` — cron: agenda a sincronização de todas as conexões. Garante dados
      atualizados mesmo sem webhook (ex.: Grana rodando só em localhost).
  """
  use Oban.Worker,
    queue: :open_finance,
    max_attempts: 3,
    # Uma atualização na Pluggy dispara vários webhooks seguidos (item/updated,
    # transactions/*); basta uma sincronização para todos.
    unique: [period: 60, states: :incomplete]

  alias Grana.Accounts.{Scope, User}
  alias Grana.OpenFinance
  alias Grana.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"connection_id" => connection_id}}) do
    case OpenFinance.sync(connection_id) do
      {:ok, _} -> :ok
      # Item removido na Pluggy: o erro fica registrado na conexão; tentar de novo não ajuda.
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, OpenFinance.error_message(reason)}
    end
  end

  def perform(%Oban.Job{args: %{"user_id" => user_id, "item_id" => item_id}}) do
    with %User{} = user <- Repo.get(User, user_id),
         {:error, reason} when reason not in [:already_connected, :not_found] <-
           OpenFinance.add_connection(Scope.for_user(user), item_id) do
      {:error, OpenFinance.error_message(reason)}
    else
      _ -> :ok
    end
  end

  def perform(%Oban.Job{args: _}) do
    OpenFinance.enqueue_sync_all()
    :ok
  end
end
