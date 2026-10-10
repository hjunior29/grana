defmodule GranaWeb.PluggyWebhookController do
  @moduledoc """
  Recebe os webhooks da Pluggy (`POST /webhooks/pluggy`).

  Só aceita chamadas com o header secreto que o próprio Grana registra junto do
  webhook (ver `Grana.OpenFinance.register_webhook/1`); o segredo identifica o
  usuário dono da aplicação na Pluggy. Responde rápido — a Pluggy considera falha
  após 10s — e deixa o trabalho para um job Oban.
  """
  use GranaWeb, :controller

  alias Grana.Accounts.{Scope, User}
  alias Grana.OpenFinance

  def create(conn, params) do
    if OpenFinance.webhook_url() do
      case webhook_user(conn) do
        %User{} = user ->
          OpenFinance.handle_webhook(Scope.for_user(user), params)
          send_resp(conn, 200, "")

        # 401 não é retentado pela Pluggy, o que convém para chamadas forjadas.
        nil ->
          send_resp(conn, 401, "")
      end
    else
      # Webhook desligado (sem PLUGGY_WEBHOOK_URL): a rota se comporta como inexistente.
      send_resp(conn, 404, "")
    end
  end

  defp webhook_user(conn) do
    case get_req_header(conn, OpenFinance.webhook_secret_header()) do
      [secret | _] -> OpenFinance.webhook_user(secret)
      [] -> nil
    end
  end
end
