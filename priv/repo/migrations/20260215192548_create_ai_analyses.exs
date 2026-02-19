defmodule Grana.Repo.Migrations.CreateAiAnalyses do
  use Ecto.Migration

  def change do
    create table(:ai_analyses) do
      add :prompt, :text
      add :filters_json, :map
      add :result_json, :map, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:ai_analyses, [:user_id])
  end
end
