defmodule Grana.Repo.Migrations.AddCustomCreditLimitToOpenFinanceAccounts do
  use Ecto.Migration

  # Limite que o próprio cliente definiu no app do banco (pode ser menor que o
  # aprovado). É o teto real do cartão: o `availableCreditLimit` vem dele.
  def change do
    alter table(:open_finance_accounts) do
      add :custom_credit_limit, :decimal, precision: 15, scale: 2
    end
  end
end
