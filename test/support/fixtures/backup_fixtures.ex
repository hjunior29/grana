defmodule Grana.BackupFixtures do
  @moduledoc """
  Gera arquivos de backup reais (SQLite com o schema atual) sem tocar o banco do
  teste: o schema vem de uma cópia do banco de teste (`VACUUM INTO`, por uma
  conexão fora do sandbox) e um repo dinâmico separado recebe as fixtures normais
  (`user_fixture/1` etc.).
  """

  alias Grana.Repo

  @doc "Cria `path` como um banco do Grana e roda `fun` com o `Repo` apontando para ele."
  def build_backup(path, fun) do
    copy_schema(path)

    with_repo(path, :delete, fn ->
      Repo.query!("DELETE FROM users")
      fun.()
    end)
  end

  @doc "Como `build_backup/2`, mas simula um backup anterior à última migration."
  def build_old_backup(path, fun) do
    result = build_backup(path, fun)

    with_repo(path, :delete, fn ->
      Repo.query!("DELETE FROM schema_migrations WHERE version = 20261010180402")
      Repo.query!("ALTER TABLE users DROP COLUMN theme")
      Repo.query!("ALTER TABLE users DROP COLUMN visual_style")
    end)

    result
  end

  defp copy_schema(path) do
    test_db = Application.fetch_env!(:grana, Repo)[:database]
    with_repo(test_db, :wal, fn -> Repo.query!("VACUUM INTO ?", [path]) end)
  end

  defp with_repo(database, journal_mode, fun) do
    task =
      Task.async(fn ->
        {:ok, pid} =
          Repo.start_link(
            name: nil,
            database: database,
            pool: DBConnection.ConnectionPool,
            pool_size: 1,
            journal_mode: journal_mode
          )

        Repo.put_dynamic_repo(pid)

        try do
          fun.()
        after
          GenServer.stop(pid)
        end
      end)

    Task.await(task, :infinity)
  end
end
