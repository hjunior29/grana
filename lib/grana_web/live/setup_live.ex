defmodule GranaWeb.SetupLive do
  use GranaWeb, :live_view

  alias Grana.Accounts
  alias Grana.Setup
  alias GranaWeb.BackupComponents

  on_mount {GranaWeb.BackupHooks, :setup}

  @steps [:code, :welcome, :choice, :account]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} hide_nav show_appearance>
      <div id="setup" class="mx-auto max-w-xl py-6 sm:py-10">
        <ol id="setup-steps" class="mb-8 flex items-center justify-center gap-2">
          <li
            :for={{step, index} <- Enum.with_index(@steps, 1)}
            id={"setup-step-#{step}"}
            class={[
              "flex size-8 items-center justify-center rounded-full text-sm font-semibold transition-colors",
              if(step_reached?(@step, step),
                do: "bg-primary text-primary-content",
                else: "ui-text-tertiary bg-base-200"
              )
            ]}
          >
            {index}
          </li>
        </ol>

        <%= case @step do %>
          <% :code -> %>
            <div id="setup-code-step">
              <.page_header title="Configuração inicial">
                <:actions><.icon name="hero-key" class="size-6 text-primary" /></:actions>
              </.page_header>
              <div class="card bg-base-200 p-6 sm:p-8">
                <p class="ui-body ui-text-secondary mb-5">
                  Esta instância ainda não tem dono. Para provar que você tem acesso ao servidor,
                  digite o código impresso no log do Grana, em
                  <code class="ui-rounded-field bg-base-100 px-1">journalctl -u grana -f</code>
                  ou <code class="ui-rounded-field bg-base-100 px-1">docker logs grana</code>.
                </p>
                <.form for={@code_form} id="setup-code-form" phx-submit="verify_code">
                  <.input
                    field={@code_form[:code]}
                    type="text"
                    label="Código do setup"
                    placeholder="XXXX-XXXX"
                    autocomplete="off"
                    autocapitalize="characters"
                    phx-mounted={JS.focus()}
                  />
                  <.button variant="primary" class="w-full" loading="Verificando…">
                    Continuar
                  </.button>
                </.form>
              </div>
            </div>
          <% :welcome -> %>
            <div id="setup-welcome-step">
              <.page_header
                title="Bem-vindo ao Grana"
                subtitle="Suas finanças, no seu servidor. Veja em 30 segundos como tudo funciona."
              />
              <div class="card bg-base-200 p-6 sm:p-8">
                <ul class="mb-6 flex flex-col gap-4">
                  <li :for={item <- how_it_works()} class="flex gap-3">
                    <.icon name={item.icon} class="mt-0.5 size-6 shrink-0 text-primary" />
                    <div>
                      <p class="ui-body font-semibold">{item.title}</p>
                      <p class="ui-body ui-text-secondary">{item.text}</p>
                    </div>
                  </li>
                </ul>
                <.button
                  id="setup-continue"
                  type="button"
                  variant="primary"
                  class="w-full"
                  phx-click="goto_choice"
                >
                  Continuar <.icon name="hero-arrow-right" class="size-4" />
                </.button>
              </div>
            </div>
          <% :choice -> %>
            <div id="setup-choice-step">
              <.page_header
                title="Como quer começar?"
                subtitle="Comece do zero ou traga os dados de outra instalação."
              />
              <div class="card bg-base-200 p-6 sm:p-8">
                <div class="flex flex-col gap-3">
                  <.button
                    id="setup-new-install"
                    type="button"
                    variant="primary"
                    class="justify-start"
                    icon="hero-sparkles"
                    phx-click="goto_account"
                  >
                    Nova instalação
                  </.button>
                  <.button
                    id="setup-restore"
                    type="button"
                    variant="secondary"
                    class="justify-start"
                    icon="hero-archive-box-arrow-down"
                    phx-click="goto_restore"
                  >
                    Restaurar um backup
                  </.button>
                </div>
              </div>
            </div>
          <% :restore -> %>
            <div id="setup-restore-step">
              <.page_header
                title="Restaurar um backup"
                subtitle="Envie o arquivo .db baixado em Configurações → Backup."
              />
              <div class="card bg-base-200 p-6 sm:p-8">
                <BackupComponents.restore_panel
                  stage={@restore_stage}
                  uploads={@uploads}
                  analysis={@restore_analysis}
                  form={@restore_form}
                  upload_error={@restore_upload_error}
                />
                <div :if={@restore_stage == :idle} class="mt-4">
                  <.button
                    id="setup-restore-back"
                    type="button"
                    variant="ghost"
                    size="sm"
                    phx-click="goto_choice"
                  >
                    Voltar
                  </.button>
                </div>
              </div>
            </div>
          <% :account -> %>
            <div id="setup-account-step">
              <.page_header
                title="Sua conta"
                subtitle="Você será o único usuário desta instância."
              />
              <div class="card bg-base-200 p-6 sm:p-8">
                <.form
                  for={@form}
                  id="setup-account-form"
                  action={~p"/users/log-in"}
                  method="post"
                  phx-change="validate"
                  phx-submit="save"
                  phx-trigger-action={@trigger_submit}
                  novalidate
                >
                  <.input
                    field={@form[:name]}
                    type="text"
                    label="Nome"
                    autocomplete="name"
                    phx-mounted={JS.focus()}
                  />
                  <.input
                    field={@form[:email]}
                    type="email"
                    label="Email"
                    autocomplete="username"
                  />
                  <.input
                    field={@form[:password]}
                    type="password"
                    label="Senha"
                    autocomplete="new-password"
                  />
                  <.input
                    field={@form[:password_confirmation]}
                    type="password"
                    label="Confirmar senha"
                    autocomplete="new-password"
                  />
                  <input type="hidden" name="user[remember_me]" value="true" />
                  <.button variant="primary" class="w-full" loading="Criando…">
                    Criar conta e entrar
                  </.button>
                </.form>
              </div>
            </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:steps, @steps)
     |> assign(:step, :code)
     |> assign(:code, nil)
     |> assign(:code_form, to_form(%{"code" => ""}, as: :setup))
     |> assign(:form, to_form(Accounts.change_owner(), as: "user"))
     |> assign(:trigger_submit, false)
     |> assign(:client_ip, GranaWeb.RateLimit.get_ip(socket))
     |> assign(:base_url, base_url(socket))}
  end

  @impl true
  def handle_event("verify_code", %{"setup" => %{"code" => code}}, socket) do
    with :allow <- GranaWeb.RateLimit.check(:setup_code, socket.assigns.client_ip),
         true <- Setup.verify_code(code) do
      {:noreply, assign(socket, step: :welcome, code: code)}
    else
      :deny ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Muitas tentativas. Aguarde um momento antes de tentar novamente."
         )}

      false ->
        {:noreply, put_flash(socket, :error, "Código inválido. Confira o log do servidor.")}
    end
  end

  def handle_event("goto_choice", _params, %{assigns: %{step: step}} = socket)
      when step in [:welcome, :restore] do
    {:noreply, assign(socket, :step, :choice)}
  end

  def handle_event("goto_account", _params, %{assigns: %{step: :choice}} = socket) do
    {:noreply, assign(socket, :step, :account)}
  end

  def handle_event("goto_restore", _params, %{assigns: %{step: :choice}} = socket) do
    {:noreply, assign(socket, :step, :restore)}
  end

  def handle_event("validate", %{"user" => params}, %{assigns: %{step: :account}} = socket) do
    form =
      params
      |> Accounts.change_owner(hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form(as: "user")

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"user" => params}, %{assigns: %{step: :account}} = socket) do
    params = Map.put(params, "base_url", socket.assigns.base_url)

    # O código é conferido de novo: o passo anterior só vive no estado do socket.
    if Setup.verify_code(socket.assigns.code) do
      case Accounts.register_owner(params) do
        {:ok, user} ->
          form =
            to_form(%{"email" => user.email, "password" => params["password"]}, as: "user")

          {:noreply, assign(socket, form: form, trigger_submit: true)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}

        {:error, :already_set_up} ->
          {:noreply, redirect(socket, to: ~p"/users/log-in")}
      end
    else
      {:noreply,
       socket
       |> assign(:step, :code)
       |> put_flash(:error, "O código do setup expirou. Digite o código atual do log.")}
    end
  end

  defp step_reached?(current, step), do: step_index(step) <= step_index(current)
  defp step_index(:restore), do: step_index(:account)
  defp step_index(step), do: Enum.find_index(@steps, &(&1 == step))

  defp how_it_works do
    [
      %{
        icon: "hero-cloud-arrow-up",
        title: "Seus uploads são o histórico oficial",
        text: "Envie faturas e extratos (PDF, CSV, OFX): é o que o Grana trata como verdade."
      },
      %{
        icon: "hero-link",
        title: "Open Finance mostra o hoje",
        text:
          "Opcional, via Meu Pluggy: saldos, faturas e limites atuais, e preenche só os meses sem upload."
      },
      %{
        icon: "hero-sparkles",
        title: "IA categoriza e analisa",
        text:
          "Com a sua própria chave (Gemini, OpenAI, Claude ou outro), para classificar gastos e gerar análises."
      },
      %{
        icon: "hero-server",
        title: "Tudo fica no seu servidor",
        text: "Um único arquivo SQLite. Baixe o backup quando quiser."
      }
    ]
  end

  defp base_url(socket) do
    with true <- connected?(socket),
         %URI{scheme: scheme, host: host, port: port} when is_binary(host) <-
           get_connect_info(socket, :uri) do
      URI.to_string(%URI{scheme: scheme, host: host, port: port})
    else
      _ -> nil
    end
  end
end
