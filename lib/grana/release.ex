defmodule Grana.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :grana

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Saída de emergência: imprime o link de redefinição de senha do dono. Funciona
  sem SMTP e sem login (quem roda tem acesso ao servidor).
  """
  def reset_password do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          case Grana.Accounts.get_owner() do
            nil ->
              IO.puts("Esta instância ainda não tem dono. Abra /setup para criar a conta.")

            owner ->
              {:ok, token} = Grana.Accounts.build_reset_password_token(owner)
              base_url = Grana.Accounts.public_base_url(owner)

              IO.puts("""

              Abra o link abaixo (vale por 30 minutos) para definir uma nova senha:

                #{base_url}/users/reset-password/#{token}
              """)
          end
        end)
    end

    :ok
  end

  @doc """
  Saída de emergência: apaga o SMTP salvo no banco, desligando o 2FA. Avisa se
  ainda houver SMTP no ambiente, que só se desliga removendo as variáveis.
  """
  def disable_smtp do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          if owner = Grana.Accounts.get_owner() do
            {:ok, _} = Grana.Accounts.remove_smtp_settings(owner)
            IO.puts("SMTP salvo no banco removido. O login volta a pedir só a senha.")
          end

          if Grana.Accounts.smtp_source() == :env do
            IO.puts(
              "ATENÇÃO: ainda há SMTP no ambiente (SMTP_HOST...). Remova as variáveis e reinicie para desligar o 2FA."
            )
          end
        end)
    end

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
