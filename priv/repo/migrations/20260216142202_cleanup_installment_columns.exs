defmodule Granai.Repo.Migrations.CleanupInstallmentColumns do
  use Ecto.Migration

  def change do
    # Remove installment columns added by the deleted migration
    # They will be re-added in a future step
    alter table(:transactions) do
      remove :installment_current, :integer
      remove :installment_total, :integer
      remove :installment_group_id, :string
    end
  end
end
