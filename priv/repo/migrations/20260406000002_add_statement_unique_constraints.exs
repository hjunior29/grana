defmodule Grana.Repo.Migrations.AddStatementUniqueConstraints do
  use Ecto.Migration

  def change do
    create unique_index(
             :bank_statements,
             [:user_id, :bank, :filename, :period_start, :period_end],
             name: :bank_statements_unique_upload
           )

    create unique_index(
             :investment_statements,
             [:user_id, :institution_id, :filename, :period_start, :period_end],
             name: :investment_statements_unique_upload
           )
  end
end
