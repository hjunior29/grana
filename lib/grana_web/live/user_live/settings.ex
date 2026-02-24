defmodule GranaWeb.UserLive.Settings do
  use GranaWeb, :live_view

  on_mount {GranaWeb.UserAuth, :require_sudo_mode}

  alias Grana.Accounts

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
              >
                <.input
                  field={@email_form[:email]}
                  type="email"
                  label=""
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
          <.form
            for={@ai_form}
            id="ai_form"
            phx-submit="update_ai_settings"
            phx-change="validate_ai_settings"
            autocomplete="off"
            data-form-type="other"
          >
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
              <div>
                <label class="text-sm font-medium block mb-1">Provider</label>
                <select name="user[ai_provider]" class="select select-bordered w-full">
                  <option value="gemini" selected={@ai_form[:ai_provider].value == "gemini"}>
                    Google Gemini
                  </option>
                </select>
              </div>
              <div>
                <label class="text-sm font-medium block mb-1">Modelo</label>
                <select name="user[ai_model]" class="select select-bordered w-full">
                  <option
                    value="gemini-2.0-flash"
                    selected={@ai_form[:ai_model].value == "gemini-2.0-flash"}
                  >
                    Gemini 2.0 Flash
                  </option>
                  <option
                    value="gemini-2.5-flash"
                    selected={@ai_form[:ai_model].value == "gemini-2.5-flash"}
                  >
                    Gemini 2.5 Flash
                  </option>
                  <option
                    value="gemini-2.5-pro"
                    selected={@ai_form[:ai_model].value == "gemini-2.5-pro"}
                  >
                    Gemini 2.5 Pro
                  </option>
                </select>
              </div>
            </div>
            <div class="mb-4">
              <label class="text-sm font-medium block mb-1">API Key</label>
              <div class="relative">
                <input
                  type={if @show_api_key, do: "text", else: "password"}
                  name="user[ai_api_key]"
                  value={@ai_form[:ai_api_key].value}
                  class="input input-bordered w-full pr-12"
                  autocomplete="one-time-code"
                  data-1p-ignore="true"
                  data-lpignore="true"
                  data-form-type="other"
                />
                <button
                  type="button"
                  phx-click="toggle_api_key_visibility"
                  class="absolute right-3 top-1/2 -translate-y-1/2 opacity-40 hover:opacity-70 transition-opacity"
                >
                  <.icon :if={!@show_api_key} name="hero-eye" class="size-5 cursor-pointer" />
                  <.icon :if={@show_api_key} name="hero-eye-slash" class="size-5 cursor-pointer" />
                </button>
              </div>
            </div>
            <.button class="btn btn-primary btn-sm" phx-disable-with="Salvando...">Salvar</.button>
          </.form>
        </div>

        <div class="card bg-base-200 p-6 mb-6">
          <div class="flex items-center gap-3 mb-4">
            <.icon name="hero-paint-brush" class="size-5 opacity-60" />
            <h3 class="text-lg font-semibold">Preferências</h3>
          </div>
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm">Tema</p>
              <p class="text-xs opacity-50">Escolha entre claro, escuro ou sistema</p>
            </div>
            <Layouts.theme_toggle />
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
    ai_changeset = Accounts.change_user_ai_settings(user)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:ai_form, to_form(ai_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:show_delete_modal, false)
      |> assign(:show_api_key, false)

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
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "Um link de confirmação foi enviado para o novo endereço de email."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
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
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("toggle_api_key_visibility", _params, socket) do
    {:noreply, assign(socket, :show_api_key, !socket.assigns.show_api_key)}
  end

  def handle_event("validate_ai_settings", %{"user" => params}, socket) do
    ai_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_ai_settings(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, ai_form: ai_form)}
  end

  def handle_event("update_ai_settings", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_ai_settings(user, params) do
      {:ok, updated_user} ->
        ai_changeset = Accounts.change_user_ai_settings(updated_user)

        socket =
          socket
          |> assign(:ai_form, to_form(ai_changeset))
          |> put_flash(:info, "Configurações de LLM salvas com sucesso!")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, ai_form: to_form(changeset, action: :insert))}
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

    case Accounts.delete_user(user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> redirect(to: ~p"/users/log-in")
         |> put_flash(:info, "Sua conta foi excluída permanentemente.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Erro ao excluir conta.")}
    end
  end
end
