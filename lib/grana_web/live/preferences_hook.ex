defmodule GranaWeb.PreferencesHook do
  @moduledoc """
  Persiste no servidor o tema, o estilo visual e a privacidade (ocultar valores e nomes)
  escolhidos nas Configurações. Toda tela logada assina as mudanças: ao trocar uma
  preferência, as outras abas e aparelhos abertos aplicam na hora, sem recarregar.

  Na conta compartilhada da demonstração, as preferências são da sessão de cada visitante
  (`Grana.Demo.put_session_preferences/3`): só as abas dele recebem a mudança.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Grana.Accounts
  alias Grana.Demo

  def on_mount(:default, _params, session, socket) do
    user = socket.assigns.current_scope.user
    demo_key = user.demo && session["user_token"] && Demo.session_key(session["user_token"])

    if connected?(socket) do
      if demo_key,
        do: Demo.subscribe_session(demo_key),
        else: Accounts.subscribe_preferences(user.id)
    end

    {:cont,
     socket
     |> assign(:demo_session_key, demo_key)
     |> attach_hook(:preferences, :handle_event, &handle_event/3)
     |> attach_hook(:preferences_sync, :handle_info, &handle_info/2)}
  end

  defp handle_event("set_preference", params, socket) do
    %{current_scope: %{user: user}, demo_session_key: demo_key} = socket.assigns

    result =
      if demo_key,
        do: Demo.put_session_preferences(demo_key, user, params),
        else: Accounts.update_user_preferences(user, params)

    case result do
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
