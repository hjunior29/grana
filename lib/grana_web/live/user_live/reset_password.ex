defmodule GranaWeb.UserLive.ResetPassword do
  use GranaWeb, :live_view

  alias Grana.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hide_nav>
      <.auth_card
        id="reset-password-card"
        title="Nova senha"
        subtitle="Escolha uma senha nova para a sua conta."
      >
        <.form for={@form} id="reset_password_form" phx-change="validate" phx-submit="save" novalidate>
          <.input
            field={@form[:password]}
            type="password"
            label="Nova senha"
            autocomplete="new-password"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirmar nova senha"
            autocomplete="new-password"
            required
          />
          <.button variant="primary" class="w-full" loading="Salvando…">Redefinir senha</.button>
        </.form>
      </.auth_card>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      {:ok,
       socket
       |> assign(:token, token)
       |> assign(:user, user)
       |> assign(:form, to_form(Accounts.change_user_password(user, %{}, hash_password: false)))}
    else
      {:ok,
       socket
       |> put_flash(:error, "O link de recuperação é inválido ou expirou.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form =
      socket.assigns.user
      |> Accounts.change_user_password(params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.get_user_by_reset_password_token(socket.assigns.token) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "O link de recuperação é inválido ou expirou.")
         |> push_navigate(to: ~p"/users/log-in")}

      user ->
        case Accounts.reset_user_password(user, params) do
          {:ok, {_user, expired_tokens}} ->
            GranaWeb.UserAuth.disconnect_sessions(expired_tokens)

            {:noreply,
             socket
             |> put_flash(:info, "Senha redefinida. Entre com a nova senha.")
             |> push_navigate(to: ~p"/users/log-in")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
        end
    end
  end
end
