defmodule GranaWeb.UserLive.Login do
  use GranaWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hide_nav>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Entrar</p>
            <:subtitle>
              <%= if @current_scope do %>
                Confirme sua senha para realizar ações sensíveis na sua conta.
              <% else %>
                Entre na sua instância do Grana.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <.form
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
          novalidate
        >
          <.input
            readonly={!!@current_scope}
            id="login_form_password_email"
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="email"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Senha"
            autocomplete="current-password"
          />
          <label class="flex items-center gap-2 cursor-pointer mb-4">
            <input
              type="checkbox"
              name={@form[:remember_me].name}
              value="true"
              checked
              class="checkbox checkbox-sm checkbox-primary"
            />
            <span class="text-sm">Manter conectado</span>
          </label>
          <.button class="btn btn-primary w-full">
            Entrar
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
