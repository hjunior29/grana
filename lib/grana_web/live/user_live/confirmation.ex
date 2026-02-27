defmodule GranaWeb.UserLive.Confirmation do
  use GranaWeb, :live_view

  alias Grana.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hide_nav>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>Bem vindo, {@user.email}</.header>
        </div>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
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
          <.button phx-disable-with="Confirmando..." class="btn btn-primary w-full">
            Confirmar
          </.button>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_scope do %>
            <.button phx-disable-with="Entrando..." class="btn btn-primary w-full">
              Entrar
            </.button>
          <% else %>
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
            <.button phx-disable-with="Entrando..." class="btn btn-primary w-full">
              Entrar
            </.button>
          <% end %>
        </.form>

        <p :if={!@user.confirmed_at} class="alert alert-outline mt-8">
          Dica: Se preferir senhas, você pode habilitá-las nas configurações do usuário.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Link mágico é inválido ou expirou.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
