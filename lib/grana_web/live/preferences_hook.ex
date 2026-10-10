defmodule GranaWeb.PreferencesHook do
  @moduledoc """
  Persiste no servidor o tema e o estilo visual escolhidos nos toggles
  (`Layouts.theme_toggle persist`). O navegador aplica na hora; isto só grava.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias Grana.Accounts

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :preferences, :handle_event, &handle_event/3)}
  end

  defp handle_event("set_preference", params, socket) do
    case Accounts.update_user_preferences(socket.assigns.current_scope.user, params) do
      {:ok, user} -> {:halt, assign(socket, :current_scope, Accounts.Scope.for_user(user))}
      {:error, _changeset} -> {:halt, socket}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
