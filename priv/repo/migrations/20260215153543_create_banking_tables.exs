defmodule Granai.Repo.Migrations.CreateBankingTables do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :string, null: false
      add :icon, :string
      add :color, :string
      add :is_system, :boolean, default: false, null: false
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:categories, [:user_id])
    create unique_index(:categories, [:name, :user_id])

    create table(:bank_statements) do
      add :bank, :string, null: false
      add :filename, :string, null: false
      add :status, :string, default: "processing", null: false
      add :period_start, :date
      add :period_end, :date
      add :total_transactions, :integer, default: 0
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:bank_statements, [:user_id])

    create table(:transactions) do
      add :date, :date, null: false
      add :description, :string, null: false
      add :original_description, :string
      add :amount, :decimal, null: false
      add :type, :string, null: false
      add :identifier, :string
      add :bank_statement_id, references(:bank_statements, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :category_id, references(:categories, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:transactions, [:user_id])
    create index(:transactions, [:bank_statement_id])
    create index(:transactions, [:category_id])
    create index(:transactions, [:date])

    create table(:category_rules) do
      add :pattern, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :category_id, references(:categories, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:category_rules, [:user_id])
    create unique_index(:category_rules, [:pattern, :user_id])
  end
end
