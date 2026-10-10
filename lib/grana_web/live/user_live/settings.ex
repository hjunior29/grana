defmodule GranaWeb.UserLive.Settings do
  use GranaWeb, :live_view

  # Ver a página de configurações exige apenas estar autenticado (não força
  # reautenticação, que dava a impressão de logout). As AÇÕES sensíveis abaixo
  # (alterar email/senha, excluir conta) é que exigem sudo mode, com redirect
  # gracioso para reautenticar — em vez de derrubar/quebrar a sessão.
  alias Grana.Accounts
  alias GranaWeb.AccountComponents
  alias GranaWeb.OpenFinanceComponents

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
            Provider de IA usado para análises, categorização e extração de PDFs
          </p>
          <AccountComponents.ai_form
            form={@ai_form}
            env_key={@ai_env_key}
            has_api_key={@has_ai_api_key}
            show_api_key={@show_api_key}
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
          client_id={@current_scope.user.pluggy_client_id}
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
            <Layouts.theme_toggle />
          </div>
          <div class="mt-5 flex flex-col gap-3">
            <div>
              <p class="text-sm">Estilo visual</p>
              <p class="text-xs opacity-50">Escolha a linguagem visual do app interno</p>
            </div>
            <Layouts.visual_style_toggle />
          </div>
        </div>

        <div id="diagnostics" class="card bg-base-200 p-6 mb-6">
          <div class="flex items-center gap-3 mb-1">
            <.icon name="hero-wrench-screwdriver" class="size-5 opacity-60" />
            <h3 class="text-lg font-semibold">Diagnóstico</h3>
          </div>
          <p class="text-sm opacity-50 mb-4 ml-8">
            Painéis técnicos da sua instância: filas de jobs e erros registrados.
          </p>
          <div class="flex flex-wrap gap-2">
            <.link id="diagnostics-oban" href="/admin/oban" target="_blank" class="btn btn-sm">
              <.icon name="hero-queue-list" class="size-4" /> Jobs (Oban)
            </.link>
            <.link id="diagnostics-errors" href="/admin/errors" target="_blank" class="btn btn-sm">
              <.icon name="hero-bug-ant" class="size-4" /> Erros
            </.link>
          </div>
        </div>

        <div class="card bg-base-200 border border-error/20 p-6 mb-6">
          <div class="flex items-center gap-3 mb-4">
            <.icon name="hero-exclamation-triangle" class="size-5 text-error" />
            <h3 class="text-lg font-semibold text-error">Zona de Perigo</h3>
          </div>
          <p class="text-sm opacity-60 mb-4">
            Ao excluir sua conta, todos os seus dados serão removidos permanentemente,
            incluindo extratos, transações, categorias e análises. Esta ação não pode ser desfeita.
          </p>
          <button
            phx-click="show_delete_modal"
            class="btn btn-error btn-outline btn-sm"
          >
            <.icon name="hero-trash" class="size-4" /> Excluir Minha Conta
          </button>
        </div>

        <dialog
          :if={@show_delete_modal}
          class="modal modal-open"
          phx-window-keydown="cancel_delete"
          phx-key="Escape"
        >
          <div class="modal-box">
            <h3 class="text-lg font-bold text-error">Excluir Conta Permanentemente</h3>
            <p class="py-4 opacity-70">
              Esta ação é irreversível. Todos os seus dados serão apagados.
            </p>
            <div class="modal-action">
              <button type="button" phx-click="cancel_delete" class="btn btn-ghost">Cancelar</button>
              <button phx-click="confirm_delete" class="btn btn-error">
                Excluir Permanentemente
              </button>
            </div>
          </div>
          <form method="dialog" class="modal-backdrop">
            <button phx-click="cancel_delete">close</button>
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
      |> assign(:show_delete_modal, false)

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

  def handle_event("show_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("confirm_delete", _params, socket) do
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      # Capturado antes do delete: o cascade remove os tokens, mas precisamos das
      # referências para derrubar quaisquer sessões LiveView ativas em outras abas.
      session_tokens = Accounts.list_user_session_tokens(user)

      case Accounts.delete_user(user) do
        {:ok, _} ->
          GranaWeb.UserAuth.disconnect_sessions(session_tokens)

          {:noreply,
           socket
           |> redirect(to: ~p"/users/log-in")
           |> put_flash(:info, "Sua conta foi excluída permanentemente.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Erro ao excluir conta.")}
      end
    else
      {:noreply, redirect_for_reauth(socket)}
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
end
