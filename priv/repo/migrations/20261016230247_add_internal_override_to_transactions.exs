defmodule Grana.Repo.Migrations.AddInternalOverrideToTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :internal_override, :boolean
    end
  end
end
