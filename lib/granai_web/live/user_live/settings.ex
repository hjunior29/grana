defmodule GranaiWeb.UserLive.Settings do
  use GranaiWeb, :live_view

  on_mount {GranaiWeb.UserAuth, :require_sudo_mode}

  alias Granai.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            Configurações de Conta
            <:subtitle>Gerencie seu endereço de email, senha e outras configurações</:subtitle>
          </.header>
        </div>

        <div class="divider" />

        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-4">Preferências</h3>
          <div class="flex items-center justify-between">
            <div>
              <p class="text-xs opacity-60">Tema</p>
              <p class="text-sm">Escolha entre claro, escuro ou sistema</p>
            </div>
            <Layouts.theme_toggle />
          </div>
        </div>

        <div class="divider" />

        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-4">Email</h3>
          <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
            <.input
              field={@email_form[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              required
            />
            <.button class="btn btn-primary w-full" phx-disable-with="Alterando...">Alterar Email</.button>
          </.form>
        </div>

        <div class="divider" />

        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-4">Senha</h3>
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
              label="Confirmar nova senha"
              autocomplete="new-password"
            />
            <.button class="btn btn-primary w-full" phx-disable-with="Salvando...">
              Salvar Senha
            </.button>
          </.form>
        </div>

        <div class="divider" />

        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-4 text-error">Excluir Conta</h3>
          <p class="text-sm opacity-60 mb-4">
            Ao excluir sua conta, todos os seus dados serão removidos permanentemente,
            incluindo extratos, transações, categorias e análises. Esta ação não pode ser desfeita.
          </p>
          <button
            phx-click="show_delete_modal"
            class="btn btn-error btn-outline"
          >
            <.icon name="hero-trash" class="size-4" />
            Excluir Minha Conta
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
              <button phx-click="confirm_delete" class="btn btn-error">Excluir Permanentemente</button>
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

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
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
