defmodule GranaWeb.BackupComponents do
  @moduledoc "Painel de restauração de backup (estado em `GranaWeb.BackupHooks`)."
  use GranaWeb, :html

  attr :stage, :atom, required: true, doc: ":idle ou :options"
  attr :uploads, :any, required: true
  attr :analysis, :map, default: nil
  attr :form, :any, required: true
  attr :upload_error, :string, default: nil

  def restore_panel(assigns) do
    assigns = assign(assigns, :selected, selected_user(assigns.analysis, assigns.form))

    ~H"""
    <div id="restore-panel">
      <form
        :if={@stage == :idle}
        id="restore-upload-form"
        phx-submit="restore_analyze"
        phx-change="restore_validate_upload"
        class="flex flex-col gap-3"
      >
        <.file_input upload={@uploads.backup} label="Escolher arquivo de backup (.db)" />
        <p
          :for={err <- upload_errors(@uploads.backup)}
          class="ui-body text-error"
        >
          {upload_error(err)}
        </p>
        <p :if={@upload_error} id="restore-upload-error" class="ui-body text-error">
          {@upload_error}
        </p>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <.button
            id="restore-verify"
            variant="primary"
            size="sm"
            class="w-full sm:w-auto"
            disabled={@uploads.backup.entries == []}
            loading="Verificando…"
          >
            Verificar
          </.button>
          <p :if={@uploads.backup.entries == []} class="ui-help">
            Escolha um arquivo para verificar.
          </p>
        </div>
      </form>

      <.form
        :if={@stage == :options}
        for={@form}
        id="restore-options-form"
        phx-change="restore_change"
        phx-submit="restore_apply"
        autocomplete="off"
        class="flex flex-col gap-4"
      >
        <div :if={length(@analysis.users) > 1}>
          <p class="ui-label">
            Este backup tem {length(@analysis.users)} usuários. O Grana é de uma pessoa só: escolha qual manter.
          </p>
          <label
            :for={user <- @analysis.users}
            class="ui-rounded-box ui-body mb-2 flex cursor-pointer items-center gap-3 bg-base-100/60 px-3 py-2"
          >
            <input
              type="radio"
              name="restore[user_id]"
              value={user.id}
              checked={@form[:user_id].value == to_string(user.id)}
              class="radio radio-primary radio-sm"
            />
            <span class="flex-1">{user.email}</span>
            <span class="ui-text-secondary">{user.transactions} transações</span>
          </label>
        </div>
        <input
          :if={length(@analysis.users) == 1}
          type="hidden"
          name="restore[user_id]"
          value={hd(@analysis.users).id}
        />

        <div>
          <.input
            id="restore_old_cloak_key"
            type="password"
            name="restore[old_cloak_key]"
            label="Chave de criptografia do backup (opcional)"
            value={@form[:old_cloak_key].value}
            autocomplete="off"
          />
          <p class="ui-help">
            A <code>CLOAK_KEY</code> da instância de origem. Com ela, a chave do Gemini, o CPF e as
            credenciais da Pluggy e do SMTP vêm junto; sem ela, são apagados e você cadastra de novo.
          </p>
        </div>

        <div :if={@selected && !@selected.has_password?}>
          <.input
            id="restore_new_password"
            type="password"
            name="restore[new_password]"
            label="Nova senha"
            value={@form[:new_password].value}
            autocomplete="new-password"
          />
          <p class="ui-help">
            Este usuário não tinha senha no backup (entrava por link). Defina uma, de 12 a 72 caracteres.
          </p>
        </div>

        <.notice tone={:warning}>
          Restaurar substitui todos os dados desta instância pelos do backup.
        </.notice>

        <div class="flex gap-2">
          <.button
            id="restore-apply"
            variant="primary"
            size="sm"
            class="flex-1 sm:flex-none"
            loading="Restaurando…"
          >
            Restaurar backup
          </.button>
          <.button
            id="restore-cancel"
            type="button"
            variant="ghost"
            size="sm"
            phx-click="restore_cancel"
          >
            Cancelar
          </.button>
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
