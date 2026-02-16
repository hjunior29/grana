defmodule Custo.Banking.BankStatement do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bank_statements" do
    field :bank, :string
    field :filename, :string
    field :status, :string, default: "processing"
    field :period_start, :date
    field :period_end, :date
    field :total_transactions, :integer, default: 0

    belongs_to :user, Custo.Accounts.User
    has_many :transactions, Custo.Banking.Transaction

    timestamps(type: :utc_datetime)
  end

  def changeset(statement, attrs) do
    statement
    |> cast(attrs, [
      :bank,
      :filename,
      :status,
      :period_start,
      :period_end,
      :total_transactions,
      :user_id
    ])
    |> validate_required([:bank, :filename, :user_id])
    |> validate_inclusion(:bank, ["nubank", "bradesco"])
    |> validate_inclusion(:status, ["processing", "completed", "error"])
  end
end
