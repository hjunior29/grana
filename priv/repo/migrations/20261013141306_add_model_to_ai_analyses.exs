defmodule Grana.Repo.Migrations.AddModelToAiAnalyses do
  use Ecto.Migration

  def change do
    alter table(:ai_analyses) do
      add :ai_provider, :string
      add :ai_model, :string
    end
  end
end
