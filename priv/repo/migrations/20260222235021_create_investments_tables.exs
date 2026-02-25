defmodule Grana.Repo.Migrations.CreateInvestmentsTables do
  use Ecto.Migration

  def change do
    create table(:investment_institutions) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :logo_path, :string
      add :is_system, :boolean, default: false, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:investment_institutions, [:slug, :user_id])
    create index(:investment_institutions, [:user_id])

    create table(:investment_statements) do
      add :filename, :string, null: false
      add :status, :string, default: "processing", null: false
      add :period_start, :date
      add :period_end, :date
      add :total_transactions, :integer, default: 0
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :institution_id, references(:investment_institutions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:investment_statements, [:user_id])
    create index(:investment_statements, [:institution_id])

    create table(:investment_transactions) do
      add :date, :date, null: false
      add :asset_name, :string, null: false
      add :asset_ticker, :string
      add :asset_type, :string, null: false
      add :operation, :string, null: false
      add :quantity, :decimal, default: 0
      add :unit_price, :decimal, default: 0
      add :total_amount, :decimal, null: false
      add :fees, :decimal, default: 0
      add :identifier, :string
      add :original_description, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :statement_id, references(:investment_statements, on_delete: :delete_all), null: false
      add :institution_id, references(:investment_institutions, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:investment_transactions, [:user_id])
    create index(:investment_transactions, [:statement_id])
    create index(:investment_transactions, [:institution_id])
    create index(:investment_transactions, [:date])
    create index(:investment_transactions, [:asset_type])
    create index(:investment_transactions, [:asset_ticker])
  end
end
