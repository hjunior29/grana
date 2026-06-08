defmodule Grana.Repo.Migrations.CreateInternalTransferRules do
  use Ecto.Migration

  def change do
    # Regras aprendidas quando o usuário marca/desmarca uma transferência como
    # interna. `pattern` é a contraparte normalizada (cpf:<6 dígitos> ou
    # name:<nome>), `kind` é "internal" (forçar interna) ou "external" (forçar
    # externa, sobrepõe a heurística).
    create table(:internal_transfer_rules) do
      add :pattern, :string, null: false
      add :kind, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:internal_transfer_rules, [:user_id])
    create unique_index(:internal_transfer_rules, [:user_id, :pattern])
  end
end
