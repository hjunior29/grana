defmodule GranaWeb.BackupComponents do
  @moduledoc "Painel de restauração de backup (estado em `GranaWeb.BackupHooks`)."
  use GranaWeb, :html

  attr :stage, :atom, required: true, doc: ":idle ou :options"
  attr :uploads, :any, required: true
  attr :analysis, :map, default: nil
  attr :form, :any, required: true
  attr :error, :string, default: nil

  def restore_panel(assigns) do
    assigns = assign(assigns, :selected, selected_user(assigns.analysis, assigns.form))

    ~H"""
    <div id="restore-panel">
      <p :if={@error} id="restore-error" class="alert alert-error alert-soft mb-4 text-sm">
        {@error}
      </p>

      <form
        :if={@stage == :idle}
        id="restore-upload-form"
        phx-submit="restore_analyze"
        phx-change="restore_validate_upload"
        class="flex flex-col gap-2 sm:flex-row sm:items-center"
      >
        <.live_file_input
          upload={@uploads.backup}
          class="file-input file-input-bordered file-input-sm w-full sm:flex-1"
        />
        <.button
          id="restore-verify"
          class="btn btn-primary btn-sm"
          disabled={@uploads.backup.entries == []}
          phx-disable-with="Verificando..."
        >
          Verificar
        </.button>
      </form>
      <p :for={err <- upload_errors(@uploads.backup)} class="mt-2 text-sm text-error">
        {upload_error(err)}
      </p>

      <.form
        :if={@stage == :options}
        for={@form}
        id="restore-options-form"
        phx-change="restore_change"
        phx-submit="restore_apply"
        autocomplete="off"
      >
        <div :if={length(@analysis.users) > 1} class="mb-4">
          <p class="mb-2 text-sm font-medium">
            Este backup tem {length(@analysis.users)} usuários. O Grana é de uma pessoa só: escolha qual manter.
          </p>
          <label
            :for={user <- @analysis.users}
            class="mb-1 flex cursor-pointer items-center gap-3 rounded-lg bg-base-100/60 px-3 py-2 text-sm"
          >
            <input
              type="radio"
              name="restore[user_id]"
              value={user.id}
              checked={@form[:user_id].value == to_string(user.id)}
              class="radio radio-primary radio-sm"
            />
            <span class="flex-1">{user.email}</span>
            <span class="opacity-60">{user.transactions} transações</span>
          </label>
        </div>
        <input
          :if={length(@analysis.users) == 1}
          type="hidden"
          name="restore[user_id]"
          value={hd(@analysis.users).id}
        />

        <div class="mb-4">
          <label class="mb-1 block text-sm font-medium" for="restore_old_cloak_key">
            Chave de criptografia do backup (opcional)
          </label>
          <input
            id="restore_old_cloak_key"
            type="password"
            name="restore[old_cloak_key]"
            value={@form[:old_cloak_key].value}
            autocomplete="off"
            class="input input-bordered w-full"
          />
          <p class="mt-1 text-xs opacity-60">
            A <code>CLOAK_KEY</code> da instância de origem. Com ela, a chave do Gemini, o CPF e as
            credenciais da Pluggy e do SMTP vêm junto; sem ela, são apagados e você cadastra de novo.
          </p>
        </div>

        <div :if={@selected && !@selected.has_password?} class="mb-4">
          <label class="mb-1 block text-sm font-medium" for="restore_new_password">
            Nova senha
          </label>
          <input
            id="restore_new_password"
            type="password"
            name="restore[new_password]"
            value={@form[:new_password].value}
            autocomplete="new-password"
            class="input input-bordered w-full"
          />
          <p class="mt-1 text-xs opacity-60">
            Este usuário não tinha senha no backup (entrava por link). Defina uma, de 12 a 72 caracteres.
          </p>
        </div>

        <div class="alert alert-warning alert-soft mb-4 text-sm">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
          Restaurar substitui todos os dados desta instância pelos do backup.
        </div>

        <div class="flex gap-2">
          <.button id="restore-apply" class="btn btn-primary btn-sm" phx-disable-with="Restaurando...">
            Restaurar backup
          </.button>
          <button
            id="restore-cancel"
            type="button"
            phx-click="restore_cancel"
            class="btn btn-ghost btn-sm"
          >
            Cancelar
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp upload_error(:too_large), do: "Arquivo grande demais (máximo 500 MB)."
  defp upload_error(:too_many_files), do: "Envie um arquivo por vez."
  defp upload_error(_), do: "Não foi possível enviar o arquivo."

  defp selected_user(nil, _form), do: nil

  defp selected_user(analysis, form) do
    id = form[:user_id].value
    Enum.find(analysis.users, &(to_string(&1.id) == id))
  end
end
