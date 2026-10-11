defmodule GranaWeb.UserLive.TwoFactor do
  use GranaWeb, :live_view

  alias Grana.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hide_nav>
      <.auth_card id="two-factor-card" title="Código de acesso">
        <p class="ui-body ui-text-secondary -mt-3 mb-6 text-center">
          Enviamos um código de 6 dígitos para <strong>{@masked_email}</strong>. Ele vale por 10 minutos.
        </p>
        <.form for={@form} id="two_factor_form" action={~p"/users/log-in/code"} method="post">
          <.input
            field={@form[:code]}
            type="text"
            label="Código"
            inputmode="numeric"
            autocomplete="one-time-code"
            maxlength="6"
            pattern="[0-9]{6}"
            required
            phx-mounted={JS.focus()}
          />
          <.button variant="primary" class="w-full" loading="Confirmando…">Confirmar</.button>
        </.form>
        <:footer>
          <div class="flex items-center justify-between">
            <button id="resend-code" type="button" phx-click="resend" class="link link-hover">
              Reenviar código
            </button>
            <.link navigate={~p"/users/log-in"} class="link link-hover">Voltar</.link>
          </div>
        </:footer>
      </.auth_card>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    case session["pending_2fa_user_id"] && Accounts.get_user(session["pending_2fa_user_id"]) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/users/log-in")}

      user ->
        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:masked_email, mask_email(user.email))
         |> assign(:form, to_form(%{"code" => ""}, as: nil))}
    end
  end

  @impl true
  def handle_event("resend", _params, socket) do
    case Accounts.deliver_two_factor_code(socket.assigns.user) do
      {:ok, _email} ->
        {:noreply, put_flash(socket, :info, "Enviamos um novo código.")}

      {:error, :cooldown} ->
        {:noreply, put_flash(socket, :error, "Aguarde um minuto antes de pedir outro código.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível enviar o código por email.")}
    end
  end

  defp mask_email(email) do
    [local, domain] = String.split(email, "@", parts: 2)
    String.first(local) <> "•••@" <> domain
  end
end
