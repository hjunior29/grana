defmodule Grana.Repo.Migrations.AddCompositeIndexes do
  use Ecto.Migration

  def change do
    create index(:transactions, [:user_id, :date])
    create index(:transactions, [:user_id, :type, :date])
    create index(:transactions, [:user_id, :is_internal_transfer, :date])
    create index(:investment_transactions, [:user_id, :asset_ticker])
  end
end
