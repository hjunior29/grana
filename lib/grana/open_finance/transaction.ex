defmodule Grana.OpenFinance.Transaction do
  @moduledoc """
  Transação de uma conta Open Finance, espelho do `GET /v2/transactions` da Pluggy.

  `amount` guarda o valor como a Pluggy devolve (o sinal muda de convenção entre
  conta e cartão); a direção do ponto de vista do titular está em `type`
  (`"DEBIT"` = saída, `"CREDIT"` = entrada).
  """
  use Ecto.Schema

  schema "open_finance_transactions" do
    field :pluggy_id, :string
    field :date, :date
    field :description, :string
    field :amount, :decimal
    field :currency_code, :string
    field :type, :string
    field :status, :string
    field :category, :string
    field :operation_type, :string
    field :installment_number, :integer
    field :total_installments, :integer
    field :bill_id, :string
    field :provider_id, :string
    field :synced_at, :utc_datetime

    belongs_to :account, Grana.OpenFinance.Account
    belongs_to :user, Grana.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
