defmodule Grana.Repo.Migrations.SetDecimalPrecision do
  use Ecto.Migration

  # Define precision/scale nas colunas monetárias para armazenamento consistente.
  # Money: numeric(15,2); quantidade/preço: numeric(20,8) (frações/cripto sem perda).
  def change do
    alter table(:transactions) do
      modify :amount, :decimal, precision: 15, scale: 2, from: :decimal
    end

    alter table(:investment_transactions) do
      modify :quantity, :decimal, precision: 20, scale: 8, from: :decimal
      modify :unit_price, :decimal, precision: 20, scale: 8, from: :decimal
      modify :total_amount, :decimal, precision: 15, scale: 2, from: :decimal
      modify :fees, :decimal, precision: 15, scale: 2, from: :decimal
    end

    alter table(:financial_goals) do
      modify :target_value, :decimal, precision: 15, scale: 2, from: :decimal
    end
  end
end
