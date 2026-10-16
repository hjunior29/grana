defmodule GranaWeb.BackupHooks do
  @moduledoc """
  Estado e eventos da restauração de backup (`BackupComponents.restore_panel/1`),
  compartilhados por Configurações (`:settings`, exige sudo mode) e pelo Setup
  (`:setup`, exige o código do log, guardado em `socket.assigns.code`).
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias Grana.{Accounts, Backup, Setup}

  def on_mount(context, _params, _session, socket) when context in [:settings, :setup] do
    socket =
      socket
      |> assign(:restore_context, context)
      |> assign(:restore_stage, :idle)
      |> assign(:restore_analysis, nil)
      |> assign(:restore_upload_error, nil)
      |> assign(:restore_form, restore_form(%{}))
      |> allow_upload(:backup,
        accept: :any,
        max_entries: 1,
        max_file_size: 500_000_000
      )
      |> attach_hook(:restore_events, :handle_event, &handle_event/3)

    {:cont, socket}
  end

  defp restore_form(params), do: to_form(params, as: :restore)

  defp handle_event("restore_validate_upload", _params, socket),
    do: {:halt, assign(socket, :restore_upload_error, nil)}

  defp handle_event("restore_analyze", _params, socket) do
    if authorized?(socket) do
      discard(socket.assigns.restore_analysis)

      results =
        consume_uploaded_entries(socket, :backup, fn %{path: path}, _entry ->
          {:ok, Backup.analyze(path)}
        end)

      case results do
        [{:ok, analysis}] ->
          first = hd(analysis.users)

          {:halt,
           socket
           |> assign(:restore_stage, :options)
           |> assign(:restore_analysis, analysis)
           |> assign(:restore_form, restore_form(%{"user_id" => to_string(first.id)}))}

        [{:error, reason}] ->
          {:halt,
           socket
           |> assign(:restore_stage, :idle)
           |> put_flash(:error, error_message(reason))}

        [] ->
          {:halt,
           assign(socket, :restore_upload_error, "Escolha o arquivo de backup (.db) primeiro.")}
      end
    else
      {:halt, unauthorized(socket)}
    end
  end

  defp handle_event("restore_change", %{"restore" => params}, socket) do
    {:halt, assign(socket, :restore_form, restore_form(params))}
  end

  defp handle_event("restore_cancel", _params, socket) do
    discard(socket.assigns.restore_analysis)

    {:halt,
     socket
     |> assign(:restore_stage, :idle)
     |> assign(:restore_analysis, nil)}
  end

  defp handle_event("restore_apply", %{"restore" => params}, socket) do
    if authorized?(socket) do
      apply_restore(socket, params)
    else
      {:halt, unauthorized(socket)}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp apply_restore(socket, params) do
    opts = [
      old_cloak_key: params["old_cloak_key"],
      new_password: params["new_password"],
      base_url: socket.assigns[:base_url]
    ]

    case Backup.restore(
           socket.assigns.restore_analysis,
           String.to_integer(params["user_id"]),
           opts
         ) do
      {:ok, %{cleared: cleared}} ->
        {:halt,
         socket
         |> put_flash(:info, success_message(cleared))
         |> redirect(to: "/users/log-in")}

      {:error, reason} when reason in [:wrong_cloak_key, :password_required, :password_invalid] ->
        {:halt,
         socket
         |> put_flash(:error, error_message(reason))
         |> assign(:restore_form, restore_form(Map.put(params, "new_password", "")))}

      {:error, reason} ->
        {:halt,
         socket
         |> assign(restore_stage: :idle, restore_analysis: nil)
         |> put_flash(:error, error_message(reason))}
    end
  end

  defp authorized?(%{assigns: %{restore_context: :settings, current_scope: scope}}),
    do: Accounts.sudo_mode?(scope.user)

  defp authorized?(%{assigns: %{restore_context: :setup} = assigns}),
    do: Setup.verify_code(assigns[:code])

  defp unauthorized(%{assigns: %{restore_context: :settings}} = socket),
    do: GranaWeb.UserAuth.redirect_for_reauth(socket)

  defp unauthorized(socket) do
    put_flash(socket, :error, "O código do setup expirou. Reinicie o assistente.")
  end

  defp discard(nil), do: :ok
  defp discard(%{path: path}), do: Backup.discard(path)

  defp success_message([]), do: "Backup restaurado. Entre com o email e a senha do backup."

  defp success_message(cleared) do
    "Backup restaurado. Cadastre de novo: #{Enum.map_join(cleared, ", ", &secret_label/1)}."
  end

  defp secret_label("ai_providers"), do: "chaves dos provedores de IA"
  defp secret_label("cpf"), do: "CPF"
  defp secret_label("pluggy_client_secret"), do: "credenciais da Pluggy"
  defp secret_label("pluggy_webhook_secret"), do: "segredo do webhook da Pluggy"
  defp secret_label("smtp_password"), do: "senha do SMTP"

  defp error_message(:not_sqlite), do: "O arquivo não é um banco SQLite."

  defp error_message(reason) when reason in [:corrupted, :invalid_file],
    do: "O arquivo está corrompido ou não pôde ser lido."

  defp error_message(:untrusted_objects),
    do: "O arquivo contém objetos não permitidos (views ou triggers)."

  defp error_message(:not_grana_backup), do: "Este arquivo não parece um backup do Grana."

  defp error_message(:newer_backup),
    do: "Este backup é de uma versão mais nova do Grana. Atualize esta instância primeiro."

  defp error_message(:no_users), do: "O backup não tem nenhum usuário."

  defp error_message(:wrong_cloak_key),
    do: "A chave de criptografia informada não decifra as credenciais deste backup."

  defp error_message(:password_required),
    do: "O usuário deste backup não tinha senha: defina uma nova."

  defp error_message(:password_invalid), do: "A nova senha deve ter entre 12 e 72 caracteres."
  defp error_message(_), do: "Não foi possível restaurar o backup."
end
