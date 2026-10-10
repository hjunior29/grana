defmodule Grana.Repo.Migrations.AddAiSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :ai_provider, :string, default: "gemini"
      add :ai_model, :string, default: "gemini-2.0-flash"
      add :ai_api_key, :string
    end
  end
end
