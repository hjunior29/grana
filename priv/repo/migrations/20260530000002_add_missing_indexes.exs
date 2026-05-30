defmodule Grana.Repo.Migrations.AddMissingIndexes do
  use Ecto.Migration

  def change do
    # statement_type is filtered in many banking queries (extrato vs fatura).
    create_if_not_exists index(:bank_statements, [:user_id, :statement_type])

    # FK financial_goals.category_id had no index.
    create_if_not_exists index(:financial_goals, [:category_id])
  end
end
