defmodule GranaWeb.SmtpHooks do
  @moduledoc """
  Estado e eventos do card de email (`AccountComponents.smtp_card/1`),
  compartilhados por Configurações e Onboarding.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias Grana.Accounts

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:smtp_private_key, Grana.Encrypted.Binary.private_key?())
      |> assign_smtp()
      |> attach_hook(:smtp_events, :handle_event, &handle_event/3)

    {:cont, socket}
  end

  defp assign_smtp(socket) do
    user = socket.assigns.current_scope.user

    socket
    |> assign(:smtp_source, Accounts.smtp_source())
    |> assign(:smtp_config, Accounts.smtp_config())
    |> assign(:smtp_form, to_form(Accounts.change_smtp_settings(user, default_attrs())))
    |> assign(:smtp_show_form, false)
  end

  defp default_attrs, do: %{"smtp_port" => 587, "smtp_tls" => "always"}

  defp handle_event("smtp_toggle_form", _params, socket) do
    {:halt, assign(socket, :smtp_show_form, !socket.assigns.smtp_show_form)}
  end

  defp handle_event("smtp_save", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    cond do
      socket.assigns.smtp_source == :env ->
        {:halt, put_flash(socket, :error, "O SMTP já vem do .env.")}

      !Accounts.sudo_mode?(user) ->
        {:halt, GranaWeb.UserAuth.redirect_for_reauth(socket)}

      !socket.assigns.smtp_private_key ->
        {:halt, put_flash(socket, :error, "Defina CLOAK_KEY no .env e reinicie o servidor.")}

      true ->
        case Accounts.save_smtp_settings(user, params) do
          {:ok, user} ->
            {:halt,
             socket
             |> assign(:current_scope, Accounts.Scope.for_user(user))
             |> assign_smtp()
             |> put_flash(
               :info,
               "Email de teste enviado e SMTP salvo. O login agora pede um código por email."
             )}

          {:error, changeset} ->
            {:halt,
             socket
             |> assign(:smtp_form, to_form(scrub_secret(changeset)))
             |> assign(:smtp_show_form, true)}
        end
    end
  end

  defp handle_event("smtp_remove", _params, socket) do
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      {:ok, user} = Accounts.remove_smtp_settings(user)

      {:halt,
       socket
       |> assign(:current_scope, Accounts.Scope.for_user(user))
       |> assign_smtp()
       |> put_flash(:info, "SMTP removido. O login volta a pedir só a senha.")}
    else
      {:halt, GranaWeb.UserAuth.redirect_for_reauth(socket)}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  # O changeset de erro carrega o usuário real e os params digitados; a senha, nem a
  # salva nem a digitada, volta para a tela.
  defp scrub_secret(changeset) do
    %{
      changeset
      | data: %{changeset.data | smtp_password: nil},
        changes: Map.delete(changeset.changes, :smtp_password),
        params: Map.put(changeset.params || %{}, "smtp_password", "")
    }
  end
end
