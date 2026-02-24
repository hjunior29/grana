defmodule GranaWeb.UserLive.Registration do
  use GranaWeb, :live_view

  alias Grana.Accounts
  alias Grana.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hide_nav>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Registre uma nova conta
            <:subtitle>
              Já tem uma conta?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                Entrar
              </.link>
              para acessar sua conta.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            required
            phx-mounted={JS.focus()}
          />

          <div class="flex items-start gap-2 my-4">
            <input
              type="checkbox"
              id="terms_checkbox"
              phx-click="toggle_terms"
              checked={@terms_accepted}
              class="checkbox checkbox-primary checkbox-sm mt-0.5 cursor-pointer"
            />
            <label for="terms_checkbox" class="text-sm opacity-70 cursor-pointer select-none">
              Li e concordo com os
              <.link navigate={~p"/terms"} class="text-primary hover:underline">
                Termos de Uso e Política de Privacidade
              </.link>
            </label>
          </div>

          <.button
            disabled={!@terms_accepted}
            phx-disable-with="Criando conta..."
            class="btn btn-primary w-full"
          >
            Crie sua conta
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: GranaWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok,
     socket
     |> assign_form(changeset)
     |> assign(:terms_accepted, false), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("toggle_terms", _params, socket) do
    {:noreply, assign(socket, :terms_accepted, !socket.assigns.terms_accepted)}
  end

  def handle_event("save", _params, %{assigns: %{terms_accepted: false}} = socket) do
    {:noreply,
     put_flash(socket, :error, "Você precisa aceitar os Termos de Uso para criar uma conta.")}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Um e-mail foi enviado para #{user.email}, por favor acesse-o para confirmar sua conta."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
