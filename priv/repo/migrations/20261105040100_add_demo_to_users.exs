defmodule Grana.Repo.Migrations.AddDemoToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :demo, :boolean, null: false, default: false
    end
  end
end
