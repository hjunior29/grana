defmodule GranaWeb.UserLive.ForgotPassword do
  use GranaWeb, :live_view

  alias Grana.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hide_nav>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Esqueci a senha</p>
            <:subtitle>
              <%= if @smtp? do %>
                Informe seu email e enviaremos um link para escolher uma nova senha.
              <% else %>
                Esta instância não tem email configurado, então o link é gerado no servidor.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <.form :if={@smtp?} for={@form} id="forgot_password_form" phx-submit="send">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="email"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full" phx-disable-with="Enviando...">
            Enviar link
          </.button>
        </.form>

        <div :if={!@smtp?} id="reset-instructions" class="rounded-xl bg-base-200 p-4 text-sm">
          <p class="mb-2">No servidor onde o Grana roda, execute:</p>
          <pre class="overflow-x-auto rounded bg-base-100 p-2 text-xs" phx-no-curly-interpolation>sudo -u grana /opt/grana/bin/grana-reset-password</pre>
          <p class="mt-3 mb-2">ou, com Docker:</p>
          <pre class="overflow-x-auto rounded bg-base-100 p-2 text-xs" phx-no-curly-interpolation>docker exec -u nobody grana /app/bin/grana-reset-password</pre>
          <p class="mt-3 opacity-70">Abra o link impresso para definir a nova senha.</p>
        </div>

        <div class="text-center text-sm">
          <.link navigate={~p"/users/log-in"} class="link link-hover opacity-70">
            Voltar ao login
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:smtp?, Accounts.smtp_configured?())
     |> assign(:form, to_form(%{"email" => ""}, as: "user"))
     |> assign(:client_ip, GranaWeb.RateLimit.get_ip(socket))}
  end

  @impl true
  def handle_event("send", %{"user" => %{"email" => email}}, socket) do
    case GranaWeb.RateLimit.check(:password_reset, socket.assigns.client_ip) do
      :deny ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Muitas tentativas. Aguarde um momento antes de tentar novamente."
         )}

      :allow ->
        with true <- socket.assigns.smtp?,
             %{} = user <- Accounts.get_user_by_email(email) do
          Accounts.deliver_reset_password_instructions(
            user,
            &(Accounts.public_base_url(user) <> ~p"/users/reset-password/#{&1}")
          )
        end

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Se o email estiver cadastrado, você receberá o link em instantes."
         )
         |> push_navigate(to: ~p"/users/log-in")}
    end
  end
end
