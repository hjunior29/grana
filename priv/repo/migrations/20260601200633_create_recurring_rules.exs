defmodule Grana.Repo.Migrations.CreateRecurringRules do
  use Ecto.Migration

  def change do
    create table(:recurring_rules) do
      add :pattern, :string, null: false
      add :mode, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:recurring_rules, [:user_id])
    create unique_index(:recurring_rules, [:user_id, :pattern])
  end
end
