defmodule GranaWeb.UserLive.Login do
  use GranaWeb, :live_view

  alias Grana.Accounts

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
                Você precisa reautenticar para realizar ações sensíveis na sua conta.
              <% else %>
                Não tem uma conta? <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-brand hover:underline"
                  phx-no-format
                >Cadastre-se</.link> agora.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
          novalidate
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="email"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full" phx-disable-with="Enviando...">
            Entrar com email
          </.button>
        </.form>

        <div class="divider">ou</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
          novalidate
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="email"
            required
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

        <div :if={!@current_scope} class="divider">ou</div>

        <.link
          :if={!@current_scope}
          navigate={~p"/users/register"}
          class="btn btn-outline btn-primary w-full"
        >
          Criar uma conta
        </.link>

        <div :if={!@current_scope} class="text-center mt-4">
          <.link
            navigate={~p"/terms"}
            class="text-xs opacity-50 hover:opacity-80 hover:underline transition-opacity"
          >
            Termos de Uso e Política de Privacidade
          </.link>
        </div>
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

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "Se seu email estiver no nosso sistema, você receberá instruções para entrar em breve."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:grana, Grana.Mailer)[:adapter] == Swoosh.Adapters.Local and
      not Application.get_env(:grana, :smtp_available, false)
  end
end
