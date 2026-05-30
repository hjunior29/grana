defmodule Grana.Repo.Migrations.AddAvailableBanksIndex do
  use Ecto.Migration

  def change do
    # Cobre available_banks/1 (WHERE user_id ... SELECT DISTINCT bank): vira
    # index-only scan em vez de varrer os extratos do usuário.
    create_if_not_exists index(:bank_statements, [:user_id, :bank])
  end
end
