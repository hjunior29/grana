defmodule GranaWeb.OpenFinanceHooks do
  @moduledoc """
  Estado e eventos do card Open Finance (`OpenFinanceComponents.settings_card/1`),
  compartilhados por Configurações e Onboarding.

  Uso: `on_mount GranaWeb.OpenFinanceHooks` na LiveView, que então renderiza o
  card com os assigns `open_finance_*`.
  """

  use GranaWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias Grana.Accounts
  alias Grana.Accounts.Scope
  alias Grana.OpenFinance

  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:open_finance_connecting, false)
      |> assign(:open_finance_syncing, MapSet.new())
      |> assign(:open_finance_show_item_form, false)
      |> assign(:open_finance_item_form, to_form(%{"item_id" => ""}, as: :open_finance))
      |> assign(:open_finance_private_key, Grana.Encrypted.Binary.private_key?())
      |> assign_open_finance()
      |> attach_hook(:open_finance_events, :handle_event, &handle_event/3)
      |> attach_hook(:open_finance_info, :handle_info, &handle_info/2)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Grana.PubSub, OpenFinance.topic(user.id))
    end

    {:cont, socket}
  end

  # Tudo que depende das credenciais da Pluggy; refeito quando elas mudam.
  defp assign_open_finance(socket) do
    scope = socket.assigns.current_scope
    configured = OpenFinance.configured?(scope)

    socket
    |> assign(:open_finance_configured, configured)
    |> assign(:open_finance_credentials_source, OpenFinance.credentials_source(scope))
    |> assign(:open_finance_credentials_form, to_form(OpenFinance.change_credentials(scope)))
    |> assign(:open_finance_show_credentials_form, false)
    |> assign(:open_finance_connections, open_finance_connections(scope, configured))
  end

  defp open_finance_connections(scope, true), do: OpenFinance.list_connections(scope)
  defp open_finance_connections(_scope, false), do: []

  defp reload_connections(socket) do
    assign(
      socket,
      :open_finance_connections,
      OpenFinance.list_connections(socket.assigns.current_scope)
    )
  end

  defp handle_event("open_finance_toggle_credentials_form", _params, socket) do
    {:halt,
     assign(
       socket,
       :open_finance_show_credentials_form,
       !socket.assigns.open_finance_show_credentials_form
     )}
  end

  defp handle_event("open_finance_save_credentials", %{"user" => params}, socket) do
    scope = socket.assigns.current_scope

    cond do
      # Credenciais do .env têm prioridade; salvar outras no banco não teria efeito.
      socket.assigns.open_finance_credentials_source == :env ->
        {:halt, put_flash(socket, :error, "As credenciais da Pluggy já vêm do .env.")}

      !Accounts.sudo_mode?(scope.user) ->
        {:halt, GranaWeb.UserAuth.redirect_for_reauth(socket)}

      # Sem CLOAK_KEY própria o secret seria cifrado com a chave pública de dev.
      !socket.assigns.open_finance_private_key ->
        {:halt, put_flash(socket, :error, "Defina CLOAK_KEY no .env e reinicie o servidor.")}

      true ->
        case OpenFinance.save_credentials(scope, params) do
          {:ok, user} ->
            {:halt,
             socket
             |> update_scope_user(user)
             |> put_flash(:info, "Credenciais da Pluggy verificadas e salvas (cifradas).")}

          {:error, changeset} ->
            # O changeset do erro carrega o usuário real (com o secret salvo); os erros
            # são reexibidos num changeset sem nenhum secret, nem o salvo nem o digitado.
            form =
              scope
              |> OpenFinance.change_credentials(Map.put(params, "pluggy_client_secret", ""))
              |> Map.merge(%{errors: changeset.errors, action: :update})
              |> to_form()

            {:halt,
             socket
             |> assign(:open_finance_credentials_form, form)
             |> assign(:open_finance_show_credentials_form, true)}
        end
    end
  end

  defp handle_event("open_finance_remove_credentials", _params, socket) do
    scope = socket.assigns.current_scope

    if Accounts.sudo_mode?(scope.user) do
      {:ok, user} = OpenFinance.remove_credentials(scope)

      {:halt,
       socket
       |> update_scope_user(user)
       |> put_flash(:info, "Credenciais da Pluggy removidas do Grana.")}
    else
      {:halt, GranaWeb.UserAuth.redirect_for_reauth(socket)}
    end
  end

  defp handle_event("open_finance_connect", _params, socket) do
    case OpenFinance.create_connect_token(socket.assigns.current_scope) do
      {:ok, token} ->
        {:halt,
         socket
         |> assign(:open_finance_connecting, true)
         |> push_event("pluggy:open", %{
           connect_token: token,
           connector_id: OpenFinance.meu_pluggy_connector_id()
         })}

      {:error, reason} ->
        {:halt, put_flash(socket, :error, OpenFinance.error_message(reason))}
    end
  end

  defp handle_event("pluggy_connected", %{"item_id" => item_id}, socket) do
    socket = assign(socket, :open_finance_connecting, false)
    {:halt, add_open_finance_item(socket, item_id)}
  end

  defp handle_event("pluggy_error", params, socket) do
    message =
      case params["message"] do
        message when is_binary(message) and message != "" -> "Pluggy: #{message}"
        _ -> "A conexão pelo widget da Pluggy não foi concluída."
      end

    {:halt,
     socket
     |> assign(:open_finance_connecting, false)
     |> put_flash(:error, message)}
  end

  defp handle_event("pluggy_closed", _params, socket) do
    {:halt, assign(socket, :open_finance_connecting, false)}
  end

  defp handle_event("open_finance_toggle_item_form", _params, socket) do
    {:halt,
     assign(socket, :open_finance_show_item_form, !socket.assigns.open_finance_show_item_form)}
  end

  defp handle_event(
         "open_finance_add_item",
         %{"open_finance" => %{"item_id" => item_id}},
         socket
       ) do
    {:halt, add_open_finance_item(socket, item_id)}
  end

  defp handle_event("open_finance_remove", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    connection = OpenFinance.get_connection!(scope, id)

    case OpenFinance.delete_connection(scope, connection) do
      {:ok, _} ->
        {:halt,
         socket
         |> reload_connections()
         |> put_flash(:info, "Conexão removida.")}

      {:error, reason} ->
        {:halt, put_flash(socket, :error, OpenFinance.error_message(reason))}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_info({:open_finance_synced, connection_id}, socket) do
    {:halt,
     socket
     |> assign(
       :open_finance_syncing,
       MapSet.delete(socket.assigns.open_finance_syncing, connection_id)
     )
     |> reload_connections()}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  # O usuário do scope fica desatualizado após mudar as credenciais; o struct novo
  # preserva os campos virtuais (ex.: authenticated_at, usado pelo sudo mode).
  defp update_scope_user(socket, user) do
    socket
    |> assign(:current_scope, Scope.for_user(user))
    |> assign_open_finance()
  end

  defp add_open_finance_item(socket, item_id) do
    case OpenFinance.add_connection(socket.assigns.current_scope, item_id) do
      {:ok, connection} ->
        socket
        |> reload_connections()
        |> assign(:open_finance_show_item_form, false)
        |> assign(:open_finance_item_form, to_form(%{"item_id" => ""}, as: :open_finance))
        |> assign(
          :open_finance_syncing,
          MapSet.put(socket.assigns.open_finance_syncing, connection.id)
        )
        |> put_flash(:info, "Conexão adicionada! Importando contas e transações...")

      {:error, reason} ->
        put_flash(socket, :error, OpenFinance.error_message(reason))
    end
  end
end
