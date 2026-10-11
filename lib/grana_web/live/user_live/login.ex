defmodule GranaWeb.UserLive.Login do
  use GranaWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hide_nav>
      <.auth_card id="login-card" title="Entrar" subtitle={subtitle(@current_scope)}>
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
          <label class="mb-4 flex cursor-pointer items-center gap-2">
            <input
              type="checkbox"
              name={@form[:remember_me].name}
              value="true"
              checked
              class="checkbox checkbox-sm checkbox-primary"
            />
            <span class="ui-body">Manter conectado</span>
          </label>
          <.button variant="primary" class="w-full" loading="Entrando…">Entrar</.button>
        </.form>
        <:footer>
          <.link
            :if={!@current_scope}
            id="forgot-password-link"
            navigate={~p"/users/reset-password"}
            class="link link-hover"
          >
            Esqueci a senha
          </.link>
        </:footer>
      </.auth_card>
    </Layouts.app>
    """
  end

  defp subtitle(nil), do: "Entre na sua instância do Grana."
  defp subtitle(_scope), do: "Confirme sua senha para realizar ações sensíveis na sua conta."

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
