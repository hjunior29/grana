defmodule Grana.Repo.Migrations.AddHideValuesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :hide_values, :boolean, null: false, default: false
    end
  end
end
