defmodule GranaWeb.DemoGate do
  @moduledoc """
  Portão da demonstração pública (`Grana.Demo`). Como plug, `:off` responde 404 no modo
  demonstração (painéis técnicos, webhooks, backup, código do 2FA); como `on_mount`,
  `:email_off` leva ao login as telas que dependem de email (recuperar a senha e o código
  do 2FA): o login fica aberto, com o acesso da demonstração à vista.
  """

  use GranaWeb, :verified_routes

  import Plug.Conn

  alias Grana.Demo

  def init(opts), do: opts

  def call(conn, :off) do
    if Demo.enabled?(), do: conn |> send_resp(404, "Not Found") |> halt(), else: conn
  end

  def on_mount(:email_off, _params, _session, socket) do
    if Demo.enabled?() and socket.view != GranaWeb.UserLive.Login,
      do: {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/users/log-in")},
      else: {:cont, socket}
  end
end
