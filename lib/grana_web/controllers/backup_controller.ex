defmodule GranaWeb.BackupController do
  use GranaWeb, :controller

  alias Grana.{Accounts, Backup, DataDir}

  def download(conn, _params) do
    if Accounts.sudo_mode?(conn.assigns.current_scope.user) do
      tmp = Path.join(DataDir.tmp_dir(), "download-#{System.unique_integer([:positive])}.db")

      case Backup.create(tmp) do
        :ok ->
          # Lido para a memória e apagado antes de responder: o arquivo temporário
          # não pode sobrar em disco, e o backup de uma instância pessoal é pequeno.
          content = File.read!(tmp)
          File.rm(tmp)

          send_download(conn, {:binary, content},
            filename: Backup.download_filename(),
            content_type: "application/vnd.sqlite3"
          )

        {:error, _reason} ->
          File.rm(tmp)

          conn
          |> put_flash(:error, "Não foi possível gerar o backup.")
          |> redirect(to: ~p"/users/settings?section=backup")
      end
    else
      conn
      |> put_session(:user_return_to, ~p"/users/settings?section=backup")
      |> put_flash(:error, "Por segurança, confirme seu login para baixar o backup.")
      |> redirect(to: ~p"/users/log-in")
    end
  end
end
