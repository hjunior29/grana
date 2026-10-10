defmodule Grana.Repo.Migrations.CreateOpenFinanceTables do
  use Ecto.Migration

  # Espelho local dos dados lidos via Open Finance (Pluggy). Fica separado das
  # tabelas de extratos/faturas importados (`transactions`) de propósito: por ora
  # só exibimos esses dados, sem misturar com o fluxo de upload.
  def change do
    create table(:open_finance_connections) do
      add :item_id, :string, null: false
      add :connector_id, :integer
      add :connector_name, :string
      add :connector_image_url, :string
      add :status, :string
      add :execution_status, :string
      add :error_message, :string
      add :pluggy_updated_at, :utc_datetime
      add :consent_expires_at, :utc_datetime
      add :last_synced_at, :utc_datetime
      add :sync_error, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:open_finance_connections, [:item_id])
    create index(:open_finance_connections, [:user_id])

    create table(:open_finance_accounts) do
      add :pluggy_id, :string, null: false
      add :type, :string, null: false
      add :subtype, :string
      add :name, :string
      add :marketing_name, :string
      add :number, :string
      add :owner, :string
      add :currency_code, :string
      add :balance, :decimal, precision: 15, scale: 2
      add :transfer_number, :string
      add :automatically_invested_balance, :decimal, precision: 15, scale: 2
      add :credit_limit, :decimal, precision: 15, scale: 2
      add :available_credit_limit, :decimal, precision: 15, scale: 2
      add :minimum_payment, :decimal, precision: 15, scale: 2
      add :balance_close_date, :date
      add :balance_due_date, :date
      add :brand, :string
      add :level, :string
      add :synced_at, :utc_datetime, null: false

      add :connection_id, references(:open_finance_connections, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:open_finance_accounts, [:pluggy_id])
    create index(:open_finance_accounts, [:connection_id])
    create index(:open_finance_accounts, [:user_id])

    create table(:open_finance_transactions) do
      add :pluggy_id, :string, null: false
      add :date, :date, null: false
      add :description, :string
      add :amount, :decimal, precision: 15, scale: 2, null: false
      add :currency_code, :string
      add :type, :string
      add :status, :string
      add :category, :string
      add :operation_type, :string
      add :installment_number, :integer
      add :total_installments, :integer
      add :bill_id, :string
      add :provider_id, :string
      add :synced_at, :utc_datetime, null: false

      add :account_id, references(:open_finance_accounts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:open_finance_transactions, [:pluggy_id])
    create index(:open_finance_transactions, [:account_id, :date])
    create index(:open_finance_transactions, [:user_id])
  end
end
