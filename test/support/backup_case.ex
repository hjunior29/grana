defmodule Grana.BackupCase do
  @moduledoc """
  Para testes de backup/restauração, que precisam de transações reais: o SQLite
  não faz `VACUUM` nem `DETACH` dentro da transação do Sandbox. Roda o Repo em
  modo `:auto` e limpa o banco antes e depois — por isso os testes são síncronos.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Grana.Repo

  using do
    quote do
      alias Grana.Repo

      import Ecto.Query
      import Grana.BackupCase, only: [count: 1]
    end
  end

  setup do
    Sandbox.mode(Repo, :auto)
    wipe()

    on_exit(fn ->
      wipe()
      Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

  def count(table), do: Repo.aggregate(table, :count)

  defp wipe do
    Grana.DataDir.tmp_dir()
    |> Path.join("restore-*.db")
    |> Path.wildcard()
    |> Enum.each(&File.rm/1)

    %{rows: rows} =
      Repo.query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'schema_migrations'"
      )

    Repo.transaction(fn ->
      Repo.query!("PRAGMA defer_foreign_keys = ON")
      Enum.each(rows, fn [table] -> Repo.query!(~s|DELETE FROM "#{table}"|) end)
    end)
  end
end
