defmodule Grana.Repo.Migrations.AddInternalTransferField do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :is_internal_transfer, :boolean, default: false, null: false
    end

    create index(:transactions, [:user_id, :is_internal_transfer])
  end
end
