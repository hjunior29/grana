defmodule Grana.Repo.Migrations.CreateSavedSearches do
  use Ecto.Migration

  def change do
    create table(:saved_searches) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :query, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:saved_searches, [:user_id, :name])
  end
end
