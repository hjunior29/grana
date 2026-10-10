defmodule Grana.Repo.Migrations.AddPreferencesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :theme, :string, null: false, default: "system"
      add :visual_style, :string, null: false, default: "default"
    end
  end
end
