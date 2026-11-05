defmodule Grana.Repo.Migrations.AddAiSpecialistsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :ai_specialists, :map, null: false, default: %{}
    end
  end
end
