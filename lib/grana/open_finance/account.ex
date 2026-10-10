defmodule Grana.OpenFinance.Account do
  @moduledoc """
  Conta (corrente, poupança ou cartão de crédito) de uma conexão Open Finance:
  o retrato atual (saldo, limite, vencimento) do `GET /accounts` da Pluggy.
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
    field :custom_credit_limit, :decimal
    field :minimum_payment, :decimal
    field :balance_close_date, :date
    field :balance_due_date, :date
    field :brand, :string
    field :level, :string
    field :synced_at, :utc_datetime

    belongs_to :connection, Grana.OpenFinance.Connection
    belongs_to :user, Grana.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def credit_card?(%__MODULE__{type: type}), do: type == "CREDIT"

  @doc """
  Teto real do cartão: o limite definido pelo cliente no app do banco quando é
  menor que o aprovado (o disponível é calculado sobre ele), senão o aprovado.
  """
  def effective_credit_limit(%__MODULE__{credit_limit: limit, custom_credit_limit: custom})
      when is_struct(limit, Decimal) and is_struct(custom, Decimal) do
    if Decimal.lt?(custom, limit), do: custom, else: limit
  end

  def effective_credit_limit(%__MODULE__{credit_limit: limit}), do: limit

  def kind_label(%__MODULE__{subtype: "SAVINGS_ACCOUNT"}), do: "Poupança"
  def kind_label(%__MODULE__{}), do: "Conta corrente"

  # "VISA INFINITE PRIME" → "Visa Infinite Prime"; "platinum" → "Platinum".
  def card_name(%__MODULE__{} = card) do
    (card.marketing_name || card.name || "Cartão")
    |> String.downcase()
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
