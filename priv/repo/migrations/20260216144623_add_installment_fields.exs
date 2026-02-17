defmodule Granai.Repo.Migrations.AddInstallmentFields do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :installment_current, :integer
      add :installment_total, :integer
      add :installment_group_id, :string
    end

    create index(:transactions, [:installment_group_id])
  end
end
