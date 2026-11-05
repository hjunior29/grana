defmodule Grana.Banking.BankStatement do
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
    field :ai_provider, :string
    field :ai_model, :string

    # "upload" (arquivo importado) ou "open_finance" (extrato/fatura virtual que
    # cobre um período sem upload; definido pelo Grana, nunca pelo usuário).
    field :source, :string, default: "upload"
    field :external_id, :string

    belongs_to :user, Grana.Accounts.User
    belongs_to :open_finance_account, Grana.OpenFinance.Account
    has_many :transactions, Grana.Banking.Transaction

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
      :ai_provider,
      :ai_model
    ])
    |> validate_required([:bank, :filename, :user_id])
    |> validate_inclusion(:status, ["processing", "completed", "error"])
    |> validate_inclusion(:statement_type, ["extrato", "fatura"])
    |> unique_constraint([:user_id, :bank, :filename, :period_start, :period_end],
      name: :bank_statements_unique_upload,
      message: "este extrato já foi importado anteriormente"
    )
    |> unique_constraint([:user_id, :bank, :filename, :period_start, :period_end],
      name: :bank_statements_user_id_bank_filename_period_start_period_end_index,
      message: "este extrato já foi importado anteriormente"
    )
  end
end
