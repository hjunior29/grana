defmodule Granai.Banking.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transactions" do
    field :date, :date
    field :description, :string
    field :original_description, :string
    field :amount, :decimal
    field :type, :string
    field :identifier, :string

    belongs_to :bank_statement, Granai.Banking.BankStatement
    belongs_to :user, Granai.Accounts.User
    belongs_to :category, Granai.Banking.Category

    timestamps(type: :utc_datetime)
  end

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :date,
      :description,
      :original_description,
      :amount,
      :type,
      :identifier,
      :bank_statement_id,
      :user_id,
      :category_id
    ])
    |> validate_required([:date, :description, :amount, :type, :bank_statement_id, :user_id])
    |> validate_inclusion(:type, ["credit", "debit"])
  end
end
