defmodule Grana.Repo.Migrations.AddStatementTypeToBankStatements do
  use Ecto.Migration

  def change do
    alter table(:bank_statements) do
      add :statement_type, :string, default: "extrato"
    end
  end
end
