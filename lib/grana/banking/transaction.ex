defmodule Grana.Banking.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transactions" do
    field :date, :date
    field :description, :string
    field :original_description, :string
    field :amount, :decimal
    field :type, :string
    field :identifier, :string
    field :installment_current, :integer
    field :installment_total, :integer
    field :installment_group_id, :string
    field :is_internal_transfer, :boolean, default: false

    belongs_to :bank_statement, Grana.Banking.BankStatement
    belongs_to :user, Grana.Accounts.User
    belongs_to :category, Grana.Banking.Category

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
      :installment_current,
      :installment_total,
      :installment_group_id,
      :is_internal_transfer,
      :bank_statement_id,
      :user_id,
      :category_id
    ])
    |> validate_required([:date, :description, :amount, :type, :bank_statement_id, :user_id])
    |> validate_inclusion(:type, ["credit", "debit"])
  end
end
