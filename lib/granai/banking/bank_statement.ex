defmodule Granai.Banking.BankStatement do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bank_statements" do
    field :bank, :string
    field :filename, :string
    field :status, :string, default: "processing"
    field :statement_type, :string, default: "extrato"
    field :period_start, :date
    field :period_end, :date
    field :total_transactions, :integer, default: 0

    belongs_to :user, Granai.Accounts.User
    has_many :transactions, Granai.Banking.Transaction

    timestamps(type: :utc_datetime)
  end

  def changeset(statement, attrs) do
    statement
    |> cast(attrs, [
      :bank,
      :filename,
      :status,
      :statement_type,
      :period_start,
      :period_end,
      :total_transactions,
      :user_id
    ])
    |> validate_required([:bank, :filename, :user_id])
    |> validate_inclusion(:bank, ["nubank", "bradesco"])
    |> validate_inclusion(:status, ["processing", "completed", "error"])
    |> validate_inclusion(:statement_type, ["extrato", "fatura"])
  end
end
