defmodule GranaWeb.UserLive.Login do
  use GranaWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hide_nav>
      <.auth_card id="login-card" title="Entrar" subtitle={subtitle(@current_scope, @demo)}>
        <.notice
          :if={@demo && !@current_scope}
          id="demo-credentials"
          title="Acesso da demonstração"
          class="mb-6"
        >
          <dl class="ui-demo-credentials">
            <dt>Email</dt>
            <dd>{@demo.email}</dd>
            <dt>Senha</dt>
            <dd>{@demo.password}</dd>
          </dl>
        </.notice>
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
            value={if @demo && !@current_scope, do: @demo.password}
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
            :if={!@current_scope && !@demo}
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

  defp subtitle(nil, nil), do: "Entre na sua instância do Grana."
  defp subtitle(nil, _demo), do: "Entre na conta da demonstração com o acesso abaixo."

  defp subtitle(_scope, _demo),
    do: "Confirme sua senha para realizar ações sensíveis na sua conta."

  @impl true
  def mount(_params, _session, socket) do
    # Na demonstração pública o acesso é um só e vem preenchido.
    demo = if Grana.Demo.enabled?(), do: Grana.Demo.credentials()

    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)]) ||
        (demo && demo.email)

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false, demo: demo)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
