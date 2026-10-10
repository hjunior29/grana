defmodule Grana.OpenFinance.Account do
  @moduledoc """
  Conta (corrente, poupança ou cartão de crédito) de uma conexão Open Finance.
  Espelho do `GET /accounts` da Pluggy, regravado a cada sincronização.
  """
  use Ecto.Schema

  schema "open_finance_accounts" do
    field :pluggy_id, :string
    field :type, :string
    field :subtype, :string
    field :name, :string
    field :marketing_name, :string
    field :number, :string
    field :owner, :string
    field :currency_code, :string
    field :balance, :decimal
    field :transfer_number, :string
    field :automatically_invested_balance, :decimal
    field :credit_limit, :decimal
    field :available_credit_limit, :decimal
    field :minimum_payment, :decimal
    field :balance_close_date, :date
    field :balance_due_date, :date
    field :brand, :string
    field :level, :string
    field :synced_at, :utc_datetime

    belongs_to :connection, Grana.OpenFinance.Connection
    belongs_to :user, Grana.Accounts.User
    has_many :transactions, Grana.OpenFinance.Transaction

    timestamps(type: :utc_datetime)
  end

  def credit_card?(%__MODULE__{type: type}), do: type == "CREDIT"
end
