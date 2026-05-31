defmodule Grana.Investments.Statement do
  use Ecto.Schema
  import Ecto.Changeset

  schema "investment_statements" do
    field :filename, :string
    field :status, :string, default: "processing"
    field :period_start, :date
    field :period_end, :date
    field :total_transactions, :integer, default: 0

    belongs_to :user, Grana.Accounts.User
    belongs_to :institution, Grana.Investments.Institution

    has_many :transactions, Grana.Investments.Transaction, foreign_key: :statement_id

    timestamps(type: :utc_datetime)
  end

  def changeset(statement, attrs) do
    statement
    |> cast(attrs, [
      :filename,
      :status,
      :period_start,
      :period_end,
      :total_transactions,
      :user_id,
      :institution_id
    ])
    |> validate_required([:filename, :user_id, :institution_id])
    |> validate_inclusion(:status, ["processing", "completed", "error"])
    |> unique_constraint([:user_id, :institution_id, :filename, :period_start, :period_end],
      name: :investment_statements_unique_upload,
      message: "este extrato já foi importado anteriormente"
    )
  end
end
