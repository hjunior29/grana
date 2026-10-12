defmodule GranaWeb.PreferencesHook do
  @moduledoc """
  Persiste no servidor o tema, o estilo visual e a privacidade (ocultar valores e nomes)
  escolhidos nas Configurações. Toda tela logada assina as mudanças: ao trocar uma
  preferência, as outras abas e aparelhos abertos aplicam na hora, sem recarregar.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Grana.Accounts

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket),
      do: Accounts.subscribe_preferences(socket.assigns.current_scope.user.id)

    {:cont,
     socket
     |> attach_hook(:preferences, :handle_event, &handle_event/3)
     |> attach_hook(:preferences_sync, :handle_info, &handle_info/2)}
  end

  defp handle_event("set_preference", params, socket) do
    case Accounts.update_user_preferences(socket.assigns.current_scope.user, params) do
      {:ok, user} -> {:halt, assign(socket, :current_scope, Accounts.Scope.for_user(user))}
      {:error, _changeset} -> {:halt, socket}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  # Só os campos de preferência: o resto do usuário (como `authenticated_at`, do modo
  # sudo) é da sessão de cada aba.
  defp handle_info({:preferences_updated, fields}, socket) do
    user = struct(socket.assigns.current_scope.user, fields)
    {:halt, assign(socket, :current_scope, Accounts.Scope.for_user(user))}
  end

  defp handle_info(_message, socket), do: {:cont, socket}
end
