defmodule Grana.Investments.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  @asset_types ~w(acao fii etf bdr renda_fixa tesouro cripto fundo nota_fiscal debenture precatorio recebiveis cri cra op_estruturada outro)
  @operations ~w(compra venda dividendo jcp rendimento amortizacao taxa outro)

  schema "investment_transactions" do
    field :date, :date
    field :asset_name, :string
    field :asset_ticker, :string
    field :asset_type, :string
    field :operation, :string
    field :quantity, :decimal, default: Decimal.new(0)
    field :unit_price, :decimal, default: Decimal.new(0)
    field :total_amount, :decimal
    field :fees, :decimal, default: Decimal.new(0)
    field :identifier, :string
    field :original_description, :string

    belongs_to :user, Grana.Accounts.User
    belongs_to :statement, Grana.Investments.Statement
    belongs_to :institution, Grana.Investments.Institution

    timestamps(type: :utc_datetime)
  end

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :date, :asset_name, :asset_ticker, :asset_type, :operation,
      :quantity, :unit_price, :total_amount, :fees, :identifier,
      :original_description, :user_id, :statement_id, :institution_id
    ])
    |> validate_required([:date, :asset_name, :asset_type, :operation, :total_amount, :user_id, :statement_id])
    |> validate_inclusion(:asset_type, @asset_types)
    |> validate_inclusion(:operation, @operations)
  end

  def asset_types, do: @asset_types
  def operations, do: @operations
end
