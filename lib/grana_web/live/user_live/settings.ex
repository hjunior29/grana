defmodule GranaWeb.UserLive.Settings do
  use GranaWeb, :live_view

  # Ver a página de configurações exige apenas estar autenticado (não força
  # reautenticação, que dava a impressão de logout). As AÇÕES sensíveis abaixo
  # (alterar email/senha, excluir conta) é que exigem sudo mode, com redirect
  # gracioso para reautenticar — em vez de derrubar/quebrar a sessão.
  alias Grana.Accounts
  alias Grana.Diagnostics
  alias GranaWeb.AccountComponents
  alias GranaWeb.AiComponents
  alias GranaWeb.BackupComponents
  alias GranaWeb.OpenFinanceComponents

  on_mount {GranaWeb.BackupHooks, :settings}
  on_mount GranaWeb.AiSettingsHooks
  on_mount GranaWeb.SmtpHooks
  on_mount GranaWeb.OpenFinanceHooks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-xl mx-auto">
        <div class="mb-4 sm:mb-8 text-center sm:text-left">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Configurações</h1>
          <p class="text-xs sm:text-sm opacity-60 mt-1">
            Gerencie sua conta, preferências e integrações
          </p>
        </div>

        <div class="card bg-base-200 p-6 mb-6">
          <div class="flex items-center gap-3 mb-4">
            <.icon name="hero-user-circle" class="size-5 opacity-60" />
            <h3 class="text-lg font-semibold">Conta</h3>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <h4 class="text-sm font-medium opacity-70 mb-3">Email</h4>
              <.form
                for={@email_form}
                id="email_form"
                phx-submit="update_email"
                phx-change="validate_email"
                novalidate
              >
                <.input
                  field={@email_form[:email]}
                  type="email"
                  label="Endereço"
                  autocomplete="username"
                  required
                />
                <.button class="btn btn-primary w-full btn-sm" phx-disable-with="Alterando...">
                  Alterar Email
                </.button>
              </.form>
            </div>
            <div>
              <h4 class="text-sm font-medium opacity-70 mb-3">Senha</h4>
              <.form
                for={@password_form}
                id="password_form"
                action={~p"/users/update-password"}
                method="post"
                phx-change="validate_password"
                phx-submit="update_password"
                phx-trigger-action={@trigger_submit}
                novalidate
              >
                <input
                  name={@password_form[:email].name}
                  type="hidden"
                  id="hidden_user_email"
                  autocomplete="username"
                  value={@current_email}
                />
                <.input
                  field={@password_form[:password]}
                  type="password"
                  label="Nova senha"
                  autocomplete="new-password"
                  required
                />
                <.input
                  field={@password_form[:password_confirmation]}
                  type="password"
                  label="Confirmar"
                  autocomplete="new-password"
                />
                <.button class="btn btn-primary w-full btn-sm" phx-disable-with="Salvando...">
                  Salvar Senha
                </.button>
              </.form>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 p-6 mb-6">
          <div class="flex items-center gap-3 mb-1">
            <.icon name="hero-cpu-chip" class="size-5 opacity-60" />
            <h3 class="text-lg font-semibold">LLM</h3>
          </div>
          <p class="text-sm opacity-50 mb-4 ml-8">
            Provedores de IA para análises, categorização e leitura de PDFs. Os modelos vêm direto da API de cada provedor.
          </p>
          <AiComponents.providers_panel
            providers={@ai_providers}
            selected_ref={@ai_selected_ref}
            default_form={@ai_default_form}
            default_model={@ai_default_model}
            models={@ai_models}
            form={@ai_form}
            show_form={@ai_show_form}
          />
        </div>

        <AccountComponents.smtp_card
          source={@smtp_source}
          config={@smtp_config}
          form={@smtp_form}
          show_form={@smtp_show_form}
          private_key={@smtp_private_key}
        />

        <OpenFinanceComponents.settings_card
          configured={@open_finance_configured}
          credentials_source={@open_finance_credentials_source}
          client_id={@open_finance_client_id}
          credentials_form={@open_finance_credentials_form}
          show_credentials_form={@open_finance_show_credentials_form}
          private_key={@open_finance_private_key}
          connections={@open_finance_connections}
          connecting={@open_finance_connecting}
          syncing={@open_finance_syncing}
          show_item_form={@open_finance_show_item_form}
          item_form={@open_finance_item_form}
        />

        <div class="card bg-base-200 p-6 mb-6">
          <div class="flex items-center gap-3 mb-1">
            <.icon name="hero-identification" class="size-5 opacity-60" />
            <h3 class="text-lg font-semibold">Identidade</h3>
          </div>
          <p class="text-sm opacity-50 mb-4 ml-8">
            Usados para reconhecer transferências entre suas próprias contas (quando a contraparte é você). O CPF é guardado criptografado.
          </p>
          <.form for={@identity_form} id="identity_form" phx-submit="update_identity">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
              <.input
                field={@identity_form[:name]}
                type="text"
                label="Nome completo"
                placeholder="Como aparece nas suas transferências"
              />
              <.input
                field={@identity_form[:cpf]}
                type="text"
                label="CPF"
                placeholder="000.000.000-00"
                inputmode="numeric"
              />
            </div>
            <.button class="btn btn-primary btn-sm" phx-disable-with="Salvando...">Salvar</.button>
          </.form>
        </div>

        <div class="card bg-base-200 p-6 mb-6">
          <div class="flex items-center gap-3 mb-4">
            <.icon name="hero-paint-brush" class="size-5 opacity-60" />
            <h3 class="text-lg font-semibold">Preferências</h3>
          </div>
          <div class="flex items-center justify-between gap-4">
            <div>
              <p class="text-sm">Tema</p>
              <p class="text-xs opacity-50">Escolha entre claro, escuro ou sistema</p>
            </div>
            <Layouts.theme_toggle persist />
          </div>
          <div class="mt-5 flex flex-col gap-3">
            <div>
              <p class="text-sm">Estilo visual</p>
              <p class="text-xs opacity-50">Escolha a linguagem visual do app interno</p>
            </div>
            <Layouts.visual_style_toggle persist />
          </div>
        </div>

        <div id="backup" class="card bg-base-200 p-6 mb-6">
          <div class="flex items-center gap-3 mb-1">
            <.icon name="hero-archive-box" class="size-5 opacity-60" />
            <h3 class="text-lg font-semibold">Backup</h3>
          </div>
          <p class="text-sm opacity-50 mb-4 ml-8">
            Todos os seus dados ficam em um único arquivo.
          </p>

          <.link id="download-backup" href={~p"/users/settings/backup"} class="btn btn-sm self-start">
            <.icon name="hero-arrow-down-tray" class="size-4" /> Baixar backup
          </.link>

          <div id="backup-restore" class="mt-5 border-t border-base-content/10 pt-5">
            <h4 class="mb-2 text-sm font-medium opacity-70">Restaurar um backup</h4>
            <BackupComponents.restore_panel
              stage={@restore_stage}
              uploads={@uploads}
              analysis={@restore_analysis}
              form={@restore_form}
            />
          </div>

          <p class="mt-4 text-xs opacity-50">
            Guarde também a <code>CLOAK_KEY</code>
            (ou a pasta <code>secrets/</code>) para levar as credenciais cifradas.
          </p>
        </div>

        <div id="diagnostics" class="card bg-base-200 p-6 mb-6">
          <div class="flex items-center gap-3 mb-1">
            <.icon name="hero-server-stack" class="size-5 opacity-60" />
            <h3 class="text-lg font-semibold">Sistema</h3>
          </div>
          <p class="text-sm opacity-50 mb-5 ml-8">
            O estado da sua instância: dados, integrações, filas e erros.
          </p>

          <div class="grid grid-cols-3 gap-3 mb-5">
            <.system_tile
              id="diagnostics-db-size"
              label="Banco"
              value={Diagnostics.format_bytes(@diagnostics.database_size)}
            />
            <.system_tile
              id="diagnostics-uptime"
              label="No ar há"
              value={Diagnostics.format_uptime(@diagnostics.uptime_seconds)}
            />
            <.system_tile
              id="diagnostics-last-upload"
              label="Último upload"
              value={format_last_upload(@diagnostics.data.last_upload)}
            />
          </div>

          <h4 class="text-sm font-medium opacity-70 mb-2">Seus dados</h4>
          <div class="grid grid-cols-3 gap-3 mb-5">
            <.system_tile
              id="diagnostics-transactions"
              label="Transações"
              value={@diagnostics.data.transactions}
            />
            <.system_tile
              id="diagnostics-statements"
              label="Extratos e faturas"
              value={@diagnostics.data.statements}
            />
            <.system_tile
              id="diagnostics-categories"
              label="Categorias"
              value={@diagnostics.data.categories}
            />
          </div>

          <h4 class="text-sm font-medium opacity-70 mb-2">Integrações</h4>
          <ul id="diagnostics-integrations" class="mb-5 divide-y divide-base-content/10">
            <li
              :for={{label, source} <- @diagnostics.credentials}
              class="flex items-center justify-between gap-3 py-2 text-sm"
            >
              <span>
                {label}
                <span class="block text-xs opacity-50">
                  {integration_detail(label, @diagnostics)}
                </span>
              </span>
              <span class={["badge badge-sm", source_badge(source)]}>{source_label(source)}</span>
            </li>
          </ul>

          <h4 class="text-sm font-medium opacity-70 mb-2">Ambiente</h4>
          <dl class="mb-5 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
            <dt class="opacity-60">Endereço</dt>
            <dd>
              <code id="diagnostics-public-url" class="break-all">{@diagnostics.public_url}</code>
            </dd>
            <dt class="opacity-60">Pasta de dados</dt>
            <dd><code id="diagnostics-data-dir" class="break-all">{@diagnostics.data_dir}</code></dd>
            <dt class="opacity-60">Runtime</dt>
            <dd id="diagnostics-runtime">
              Elixir {@diagnostics.runtime.elixir} · OTP {@diagnostics.runtime.otp} · SQLite {@diagnostics.runtime.sqlite}
            </dd>
          </dl>

          <div class="flex flex-wrap gap-2">
            <.link id="diagnostics-oban" href="/admin/oban" target="_blank" class="btn btn-sm">
              <.icon name="hero-queue-list" class="size-4" /> Fila de jobs
              <span
                :if={@diagnostics.jobs.pending > 0}
                id="diagnostics-jobs-pending"
                class="badge badge-info badge-sm"
              >
                {@diagnostics.jobs.pending}
              </span>
              <span
                :if={@diagnostics.jobs.failed > 0}
                id="diagnostics-jobs-failed"
                class="badge badge-error badge-sm"
              >
                {@diagnostics.jobs.failed} com falha
              </span>
            </.link>
            <.link id="diagnostics-errors" href="/admin/errors" target="_blank" class="btn btn-sm">
              <.icon name="hero-bug-ant" class="size-4" /> Erros registrados
              <span
                :if={@diagnostics.unresolved_errors > 0}
                id="diagnostics-errors-count"
                class="badge badge-warning badge-sm"
              >
                {@diagnostics.unresolved_errors}
              </span>
            </.link>
          </div>
        </div>

        <div class="card bg-base-200 border border-error/20 p-6 mb-6">
          <div class="flex items-center gap-3 mb-4">
            <.icon name="hero-exclamation-triangle" class="size-5 text-error" />
            <h3 class="text-lg font-semibold text-error">Zona de Perigo</h3>
          </div>
          <p class="text-sm opacity-60 mb-4">
            Apagar todos os dados remove sua conta, extratos, transações, categorias, análises e
            conexões, e volta a instância ao assistente de configuração. Faça um backup antes:
            esta ação não pode ser desfeita.
          </p>
          <button
            id="show-reset-modal"
            phx-click="show_reset_modal"
            class="btn btn-error btn-outline btn-sm"
          >
            <.icon name="hero-trash" class="size-4" /> Apagar todos os dados
          </button>
        </div>

        <dialog
          :if={@show_reset_modal}
          id="reset-modal"
          class="modal modal-open"
          phx-window-keydown="cancel_reset"
          phx-key="Escape"
        >
          <div class="modal-box">
            <h3 class="text-lg font-bold text-error">Apagar todos os dados</h3>
            <p class="py-4 opacity-70">
              Esta ação é irreversível. Confirme com a sua senha e digite <strong>APAGAR</strong>.
            </p>
            <.form for={@reset_form} id="reset-form" phx-submit="confirm_reset">
              <.input
                field={@reset_form[:password]}
                type="password"
                label="Senha"
                autocomplete="current-password"
              />
              <.input field={@reset_form[:confirmation]} type="text" label="Digite APAGAR" />
              <div class="modal-action">
                <button type="button" phx-click="cancel_reset" class="btn btn-ghost">
                  Cancelar
                </button>
                <button
                  id="confirm-reset"
                  class="btn btn-error"
                  phx-disable-with="Apagando..."
                >
                  Apagar tudo
                </button>
              </div>
              <%!-- Aparece enquanto o form está sendo enviado (classe phx-submit-loading). --%>
              <div
                id="reset-progress"
                class="mt-4 hidden items-center gap-3 rounded-lg bg-error/10 p-3 text-sm phx-submit-loading:flex"
              >
                <span class="loading loading-spinner loading-sm text-error"></span>
                Apagando todos os dados… não feche esta página.
              </div>
            </.form>
          </div>
          <form method="dialog" class="modal-backdrop">
            <button phx-click="cancel_reset">close</button>
          </form>
        </dialog>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email alterado com sucesso.")

        {:error, _} ->
          put_flash(socket, :error, "O link de confirmação é inválido ou expirou.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)
    identity_changeset = Accounts.change_user_identity(user)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:identity_form, to_form(identity_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:show_reset_modal, false)
      |> assign(:reset_form, to_form(%{"password" => "", "confirmation" => ""}, as: :reset))
      |> assign(:diagnostics, Diagnostics.summary(user))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      %{"user" => user_params} = params

      case Accounts.change_user_email(user, user_params) do
        %{valid?: true} = changeset ->
          update_email(socket, user, changeset)

        changeset ->
          {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
      end
    else
      {:noreply, redirect_for_reauth(socket)}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      %{"user" => user_params} = params

      case Accounts.change_user_password(user, user_params) do
        %{valid?: true} = changeset ->
          {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

        changeset ->
          {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
      end
    else
      {:noreply, redirect_for_reauth(socket)}
    end
  end

  def handle_event("update_identity", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_identity(user, params) do
      {:ok, updated_user} ->
        # Reavalia as transferências já importadas com a nova identidade.
        Grana.Banking.detect_internal_transfers(updated_user.id)

        socket =
          socket
          |> assign(:identity_form, to_form(Accounts.change_user_identity(updated_user)))
          |> put_flash(
            :info,
            "Identidade salva — reavaliamos suas transferências internas."
          )

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, identity_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("show_reset_modal", _params, socket) do
    {:noreply, assign(socket, :show_reset_modal, true)}
  end

  def handle_event("cancel_reset", _params, socket) do
    {:noreply, assign(socket, :show_reset_modal, false)}
  end

  def handle_event("confirm_reset", %{"reset" => params}, socket) do
    user = socket.assigns.current_scope.user

    cond do
      params["confirmation"] != "APAGAR" ->
        {:noreply, put_flash(socket, :error, "Digite APAGAR para confirmar.")}

      not Grana.Accounts.User.valid_password?(user, params["password"] || "") ->
        {:noreply, put_flash(socket, :error, "Senha incorreta.")}

      true ->
        :ok = Grana.Backup.reset_all()
        {:noreply, redirect(socket, to: ~p"/setup")}
    end
  end

  # Com SMTP, confirma o novo endereço por link; sem SMTP não há como enviar o
  # link, então a troca é direta (a ação já exige sudo mode).
  defp update_email(socket, user, changeset) do
    if Accounts.smtp_configured?() do
      Accounts.deliver_user_update_email_instructions(
        Ecto.Changeset.apply_action!(changeset, :insert),
        user.email,
        &(Accounts.public_base_url(user) <> ~p"/users/settings/confirm-email/#{&1}")
      )

      {:noreply,
       put_flash(
         socket,
         :info,
         "Um link de confirmação foi enviado para o novo endereço de email."
       )}
    else
      {:ok, updated} =
        Accounts.update_user_email_directly(user, %{email: changeset.changes.email})

      {:noreply,
       socket
       |> assign(:current_scope, Grana.Accounts.Scope.for_user(updated))
       |> assign(:current_email, updated.email)
       |> assign(
         :email_form,
         to_form(Accounts.change_user_email(updated, %{}, validate_unique: false))
       )
       |> put_flash(:info, "Email alterado com sucesso.")}
    end
  end

  defp redirect_for_reauth(socket), do: GranaWeb.UserAuth.redirect_for_reauth(socket)

  defp source_label(:env), do: ".env"
  defp source_label(:database), do: "salva (cifrada)"
  defp source_label(nil), do: "não configurada"

  defp source_badge(:env), do: "badge-info badge-soft"
  defp source_badge(:database), do: "badge-success badge-soft"
  defp source_badge(nil), do: "badge-ghost"

  defp integration_detail("Provedores de IA", d), do: d.ai_default

  defp integration_detail("Pluggy (Open Finance)", d),
    do: "#{d.open_finance_connections} conexão(ões) com bancos"

  defp integration_detail("Email (SMTP)", _d), do: "Código de login (2FA) e recuperação de senha"

  defp format_last_upload(nil), do: "nenhum"
  defp format_last_upload(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%d/%m/%Y")
  defp format_last_upload(%DateTime{} = at), do: Calendar.strftime(at, "%d/%m/%Y")

  defp format_last_upload(at) when is_binary(at),
    do: at |> String.slice(0, 10) |> format_iso_date()

  defp format_iso_date(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> Calendar.strftime(date, "%d/%m/%Y")
      _ -> iso
    end
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true

  defp system_tile(assigns) do
    ~H"""
    <div class="rounded-xl bg-base-100/60 px-3 py-2">
      <p class="text-[11px] opacity-50">{@label}</p>
      <p id={@id} class="text-lg font-semibold tabular-nums">{@value}</p>
    </div>
    """
  end
end
