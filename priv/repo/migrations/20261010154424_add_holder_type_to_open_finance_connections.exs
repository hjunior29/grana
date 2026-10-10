defmodule Grana.Repo.Migrations.AddHolderTypeToOpenFinanceConnections do
  use Ecto.Migration

  # "PF" ou "PJ" (pela identidade da Pluggy): distingue, por exemplo, duas
  # conexões Nubank do mesmo usuário (pessoa física e empresa).
  def change do
    alter table(:open_finance_connections) do
      add :holder_type, :string
    end
  end
end
