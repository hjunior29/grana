defmodule GranaWeb.AiSettingsHooks do
  @moduledoc """
  Estado e eventos do formulário de IA (`AccountComponents.ai_form/1`),
  compartilhados por Configurações e Onboarding.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias Grana.Accounts

  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:ai_form, to_form(Accounts.change_user_ai_settings(user)))
      |> assign(:show_api_key, false)
      |> assign(:has_ai_api_key, user.ai_api_key != nil)
      |> assign(:ai_env_key, Accounts.env_ai_api_key() != nil)
      |> attach_hook(:ai_settings_events, :handle_event, &handle_event/3)

    {:cont, socket}
  end

  defp handle_event("toggle_api_key_visibility", _params, socket) do
    {:halt, assign(socket, :show_api_key, !socket.assigns.show_api_key)}
  end

  defp handle_event("validate_ai_settings", %{"user" => params}, socket) do
    ai_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_ai_settings(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:halt, assign(socket, ai_form: ai_form)}
  end

  defp handle_event("update_ai_settings", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_ai_settings(user, params) do
      {:ok, updated_user} ->
        ai_changeset = Accounts.change_user_ai_settings(updated_user)

        socket =
          socket
          |> assign(:ai_form, to_form(ai_changeset))
          |> assign(:has_ai_api_key, updated_user.ai_api_key != nil)
          |> put_flash(:info, "Configurações de LLM salvas com sucesso!")

        {:halt, socket}

      {:error, changeset} ->
        {:halt, assign(socket, ai_form: to_form(changeset, action: :insert))}
    end
  end

  defp handle_event("remove_ai_api_key", _params, socket) do
    {:ok, _user} = Accounts.remove_user_ai_api_key(socket.assigns.current_scope.user)

    {:halt,
     socket
     |> assign(:has_ai_api_key, false)
     |> put_flash(:info, "API key removida.")}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
