defmodule Grana.Repo.Migrations.OpenFinanceAsStatementSource do
  use Ecto.Migration

  # O Open Finance passa a ser uma fonte como as outras para os períodos sem
  # upload: suas transações entram em `transactions`, presas a extratos/faturas
  # virtuais (`source = "open_finance"`). O espelho próprio deixa de existir.
  def up do
    alter table(:bank_statements) do
      add :source, :string, null: false, default: "upload"
      add :external_id, :string

      add :open_finance_account_id,
          references(:open_finance_accounts, on_delete: :delete_all)
    end

    create index(:bank_statements, [:open_finance_account_id])
    create index(:bank_statements, [:user_id, :source])

    alter table(:transactions) do
      add :external_id, :string
    end

    create unique_index(:transactions, [:external_id])

    alter table(:open_finance_connections) do
      add :bank, :string
    end

    drop table(:open_finance_transactions)
  end

  def down do
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

    alter table(:open_finance_connections) do
      remove :bank
    end

    drop index(:transactions, [:external_id])

    alter table(:transactions) do
      remove :external_id
    end

    drop index(:bank_statements, [:user_id, :source])
    drop index(:bank_statements, [:open_finance_account_id])

    alter table(:bank_statements) do
      remove :open_finance_account_id
      remove :external_id
      remove :source
    end
  end
end
