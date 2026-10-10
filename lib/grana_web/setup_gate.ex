defmodule GranaWeb.SetupGate do
  @moduledoc """
  Portão do assistente de setup. Com a instância sem dono, todo o app redireciona
  para `/setup`; depois que o dono existe, `/setup` deixa de existir.

  Funciona como plug (requisições HTTP) e como `on_mount` (LiveViews).
  """

  use GranaWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias Grana.Accounts

  def init(opts), do: opts

  def call(conn, :pending) do
    if Accounts.setup_required?() do
      conn
    else
      conn |> resp(404, "Not Found") |> halt()
    end
  end

  def call(conn, _complete) do
    if Accounts.setup_required?() do
      conn |> redirect(to: ~p"/setup") |> halt()
    else
      conn
    end
  end

  def on_mount(:setup_complete, _params, _session, socket) do
    if Accounts.setup_required?() do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/setup")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:setup_pending, _params, _session, socket) do
    if Accounts.setup_required?() do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/users/log-in")}
    end
  end
end
