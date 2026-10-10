defmodule Grana.Repo.Migrations.DropInvestmentsTables do
  use Ecto.Migration

  def change do
    drop table(:investment_transactions)
    drop table(:investment_statements)
    drop table(:investment_institutions)
  end
end
