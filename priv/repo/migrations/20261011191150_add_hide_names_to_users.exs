defmodule Grana.Repo.Migrations.AddHideNamesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :hide_names, :boolean, null: false, default: false
    end
  end
end
