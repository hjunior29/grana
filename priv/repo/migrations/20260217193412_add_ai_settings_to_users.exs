defmodule Granai.Repo.Migrations.AddAiSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add_if_not_exists :ai_provider, :string, default: "gemini"
      add_if_not_exists :ai_model, :string, default: "gemini-2.0-flash"
      add_if_not_exists :ai_api_key, :string
    end
  end
end
