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
  on_mount GranaWeb.ModelChoicesHook
  on_mount GranaWeb.SmtpHooks
  on_mount GranaWeb.OpenFinanceHooks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      import_queue={@import_queue}
      ai_notice={@ai_notice}
    >
      <div class="max-w-xl mx-auto">
        <.page_header
          title="Configurações"
          subtitle="Gerencie sua conta, preferências e integrações"
        />

        <.card
          id="account-settings"
          icon="hero-user-circle"
          title="Conta"
          description="Email e senha de acesso ao Grana."
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <.section title="Email de acesso">
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
                  label="Novo email"
                  autocomplete="username"
                  required
                />
                <div class="mt-2">
                  <.button
                    variant="primary"
                    size="sm"
                    class="w-full sm:w-auto"
                    loading="Alterando…"
                  >
                    Alterar email
                  </.button>
                </div>
              </.form>
            </.section>
            <.section title="Senha de acesso">
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
                  label="Confirmar nova senha"
                  autocomplete="new-password"
                />
                <div class="mt-2">
                  <.button
                    variant="primary"
                    size="sm"
                    class="w-full sm:w-auto"
                    loading="Salvando…"
                  >
                    Salvar senha
                  </.button>
                </div>
              </.form>
            </.section>
          </div>
        </.card>

        <.card
          id="ai-settings"
          icon="hero-cpu-chip"
          title="Inteligência artificial"
          description="Provedores de IA e o modelo de cada especialista: pesquisa avançada, análise, processamento e chat. Os modelos vêm direto da API de cada provedor."
        >
          <AiComponents.providers_panel
            providers={@ai_providers}
            selected_ref={@ai_selected_ref}
            default_form={@ai_default_form}
            default_model={@ai_default_model}
            models={@ai_models}
            form={@ai_form}
            show_form={@ai_show_form}
          />
          <AiComponents.specialists_panel
            :if={@ai_providers != []}
            choices={@model_choices}
            general={@ai_general}
            values={@ai_specialists}
          />
        </.card>

        <AccountComponents.smtp_card
          source={@smtp_source}
          env_fields={@smtp_env_fields}
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

        <.card
          id="identity-settings"
          icon="hero-identification"
          title="Identidade"
          description="Usados para reconhecer transferências entre suas próprias contas (quando a contraparte é você). O CPF é guardado criptografado."
        >
          <.form for={@identity_form} id="identity_form" phx-submit="update_identity">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-x-4">
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
                maxlength="14"
                phx-hook=".CpfMask"
              />
            </div>
            <div class="mt-2">
              <.button variant="primary" size="sm" class="w-full sm:w-auto" loading="Salvando…">
                Salvar identidade
              </.button>
            </div>
          </.form>
        </.card>

        <.card
          id="preferences-settings"
          icon="hero-paint-brush"
          title="Preferências"
          description="Tema, estilo visual e privacidade na tela."
        >
          <div class="flex items-center justify-between gap-4">
            <div>
              <p class="ui-body">Tema</p>
              <p class="ui-help">Escolha entre claro, escuro ou sistema</p>
            </div>
            <Layouts.theme_toggle persist />
          </div>
          <div class="flex flex-col gap-3">
            <div>
              <p class="ui-body">Estilo visual</p>
              <p class="ui-help">Escolha a linguagem visual do app interno</p>
            </div>
            <Layouts.visual_style_toggle persist grid />
          </div>
          <.section id="privacy-settings" title="Privacidade na tela" divider>
            <p class="ui-help mb-4">
              Para gravar ou compartilhar a tela: o que estiver oculto vira uma camada fosca em
              todas as páginas, na hora.
            </p>
            <div class="flex items-center justify-between gap-4">
              <div>
                <p class="ui-body">Ocultar valores</p>
                <p class="ui-help">
                  Valores em reais. Dá para ver se é receita ou despesa pela cor, mas não o número.
                </p>
              </div>
              <.switch
                id="hide-values-toggle"
                label="Ocultar valores"
                checked={@current_scope.user.hide_values}
                phx-click="set_preference"
                phx-value-hide_values={to_string(!@current_scope.user.hide_values)}
              />
            </div>
            <div class="mt-4 flex items-center justify-between gap-4">
              <div>
                <p class="ui-body">Ocultar nomes</p>
                <p class="ui-help">
                  Descrições das transações (nomes de pessoas e lojas) e nomes dos arquivos de
                  extrato.
                </p>
              </div>
              <.switch
                id="hide-names-toggle"
                label="Ocultar nomes"
                checked={@current_scope.user.hide_names}
                phx-click="set_preference"
                phx-value-hide_names={to_string(!@current_scope.user.hide_names)}
              />
            </div>
          </.section>
        </.card>

        <.card
          id="backup"
          icon="hero-archive-box"
          title="Backup"
          description="Todos os seus dados ficam em um único arquivo."
        >
          <div>
            <.button
              id="download-backup"
              href={~p"/users/settings/backup"}
              variant="secondary"
              size="sm"
              icon="hero-arrow-down-tray"
            >
              Baixar backup
            </.button>
          </div>

          <.section id="backup-restore" title="Restaurar um backup" divider>
            <BackupComponents.restore_panel
              stage={@restore_stage}
              uploads={@uploads}
              analysis={@restore_analysis}
              form={@restore_form}
              upload_error={@restore_upload_error}
            />
          </.section>

          <p class="ui-help">
            Guarde também a <code>CLOAK_KEY</code>
            (ou a pasta <code>secrets/</code>) para levar as credenciais criptografadas.
          </p>
        </.card>

        <.card
          id="diagnostics"
          icon="hero-server-stack"
          title="Sistema"
          description="O estado da sua instância: dados, integrações, filas e erros."
        >
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <.stat_tile
              id="diagnostics-db-size"
              label="Banco"
              value={Diagnostics.format_bytes(@diagnostics.database_size)}
            />
            <.stat_tile
              id="diagnostics-uptime"
              label="No ar há"
              value={Diagnostics.format_uptime(@diagnostics.uptime_seconds)}
            />
            <.stat_tile
              id="diagnostics-last-upload"
              label="Último upload"
              value={format_last_upload(@diagnostics.data.last_upload)}
            />
          </div>

          <.section title="Seus dados">
            <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
              <.stat_tile
                id="diagnostics-transactions"
                label="Transações"
                value={@diagnostics.data.transactions}
              />
              <.stat_tile
                id="diagnostics-statements"
                label="Extratos e faturas"
                value={@diagnostics.data.statements}
              />
              <.stat_tile
                id="diagnostics-categories"
                label="Categorias"
                value={@diagnostics.data.categories}
              />
            </div>
          </.section>

          <.section title="Integrações">
            <ul id="diagnostics-integrations" class="divide-y divide-base-content/10">
              <.item_row
                :for={{label, source} <- @diagnostics.credentials}
                title={label}
                subtitle={integration_detail(label, @diagnostics)}
              >
                <:tags>
                  <%= if source == :mixed do %>
                    <.tag kind="env" />
                    <.tag kind="salvo" />
                  <% else %>
                    <.tag kind={source_kind(source)}>{source_label(source)}</.tag>
                  <% end %>
                </:tags>
              </.item_row>
            </ul>
            <dl
              id="integration-sources-legend"
              class="mt-4 grid grid-cols-[auto_1fr] items-baseline gap-x-3 gap-y-2"
            >
              <dt><.tag kind="env" /></dt>
              <dd class="ui-help">
                Vem do arquivo <code>.env</code>
                do servidor. Tem prioridade sobre o que é salvo aqui e só muda editando o arquivo.
              </dd>
              <dt><.tag kind="salvo" /></dt>
              <dd class="ui-help">
                Configurado nesta tela e guardado no banco do Grana, com senhas e chaves
                criptografadas.
              </dd>
            </dl>
          </.section>

          <.section title="Ambiente">
            <dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 ui-body">
              <dt class="ui-text-secondary">Endereço</dt>
              <dd class="min-w-0">
                <code id="diagnostics-public-url" class="break-all">{@diagnostics.public_url}</code>
              </dd>
              <dt class="ui-text-secondary">Pasta de dados</dt>
              <dd class="min-w-0">
                <code id="diagnostics-data-dir" class="break-all">{@diagnostics.data_dir}</code>
              </dd>
              <dt class="ui-text-secondary">Runtime</dt>
              <dd id="diagnostics-runtime" class="min-w-0">
                Elixir {@diagnostics.runtime.elixir} · OTP {@diagnostics.runtime.otp} · SQLite {@diagnostics.runtime.sqlite}
              </dd>
            </dl>
          </.section>

          <div class="flex flex-wrap gap-2">
            <.button
              id="diagnostics-oban"
              href="/admin/oban"
              target="_blank"
              variant="secondary"
              size="sm"
              icon="hero-queue-list"
            >
              Fila de jobs
              <.tag :if={@diagnostics.jobs.pending > 0} id="diagnostics-jobs-pending" kind="pendente">
                {@diagnostics.jobs.pending}
              </.tag>
              <.tag :if={@diagnostics.jobs.failed > 0} id="diagnostics-jobs-failed" kind="erro">
                {@diagnostics.jobs.failed} com falha
              </.tag>
            </.button>
            <.button
              id="diagnostics-errors"
              href="/admin/errors"
              target="_blank"
              variant="secondary"
              size="sm"
              icon="hero-bug-ant"
            >
              Erros registrados
              <.tag
                :if={@diagnostics.unresolved_errors > 0}
                id="diagnostics-errors-count"
                kind="erro"
              >
                {@diagnostics.unresolved_errors}
              </.tag>
            </.button>
          </div>
        </.card>

        <.card
          id="danger-zone"
          tone={:danger}
          icon="hero-exclamation-triangle"
          title="Zona de perigo"
          description="Apagar todos os dados remove sua conta, extratos, transações, categorias, análises e conexões, e volta a instância ao assistente de configuração. Faça um backup antes: esta ação não pode ser desfeita."
        >
          <div>
            <.button
              id="show-reset-modal"
              type="button"
              variant="danger"
              size="sm"
              icon="hero-trash"
              phx-click="show_reset_modal"
            >
              Apagar todos os dados
            </.button>
          </div>
        </.card>

        <.confirm_modal
          :if={@show_reset_modal}
          id="reset-modal"
          open
          title="Apagar todos os dados"
          confirm="Apagar tudo"
          loading="Apagando…"
          form={@reset_form}
          form_id="reset-form"
          confirm_id="confirm-reset"
          on_confirm="confirm_reset"
          on_cancel={JS.push("cancel_reset")}
        >
          Esta ação é irreversível. Confirme com a sua senha e digite <strong>APAGAR</strong>.
          <:fields>
            <.input
              field={@reset_form[:password]}
              type="password"
              label="Senha"
              autocomplete="current-password"
            />
            <.input field={@reset_form[:confirmation]} type="text" label="Digite APAGAR" />
            <%!-- Aparece enquanto o form está sendo enviado (classe phx-submit-loading). --%>
            <div id="reset-progress" class="mt-4 hidden phx-submit-loading:block">
              <.notice tone={:warning}>Apagando todos os dados… não feche esta página.</.notice>
            </div>
          </:fields>
        </.confirm_modal>
      </div>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CpfMask">
      const format = (value) => {
        const d = value.replace(/\D/g, "").slice(0, 11)
        return d
          .replace(/^(\d{3})(\d)/, "$1.$2")
          .replace(/^(\d{3})\.(\d{3})(\d)/, "$1.$2.$3")
          .replace(/^(\d{3})\.(\d{3})\.(\d{3})(\d)/, "$1.$2.$3-$4")
      }

      export default {
        mounted() {
          this.apply = () => { this.el.value = format(this.el.value) }
          this.el.addEventListener("input", this.apply)
          this.apply()
        },
        updated() {
          this.apply()
        }
      }
    </script>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email alterado.")

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
      |> assign(:reset_form, reset_form())
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
            "Identidade salva. Reavaliamos suas transferências internas."
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
        {:noreply,
         assign(
           socket,
           :reset_form,
           reset_form(%{}, confirmation: "Digite APAGAR para confirmar.")
         )}

      not Grana.Accounts.User.valid_password?(user, params["password"] || "") ->
        {:noreply, assign(socket, :reset_form, reset_form(params, password: "Senha incorreta."))}

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
         "Link de confirmação enviado para o novo email."
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
       |> put_flash(:info, "Email alterado.")}
    end
  end

  defp reset_form(params \\ %{}, errors \\ []) do
    params = %{
      "password" => "",
      "confirmation" => Map.get(params, "confirmation", "")
    }

    to_form(params,
      as: :reset,
      errors: Enum.map(errors, fn {field, msg} -> {field, {msg, []}} end)
    )
  end

  defp redirect_for_reauth(socket), do: GranaWeb.UserAuth.redirect_for_reauth(socket)

  defp source_label(:env), do: ".env"
  defp source_label(:database), do: "salvo no Grana"
  defp source_label(nil), do: "não configurada"

  defp source_kind(:env), do: "env"
  defp source_kind(:database), do: "salvo"
  defp source_kind(nil), do: "neutro"

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
end
