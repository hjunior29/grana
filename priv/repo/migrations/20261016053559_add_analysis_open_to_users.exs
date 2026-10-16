defmodule Grana.Repo.Migrations.AddAnalysisOpenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :analysis_open, :boolean, default: false, null: false
    end
  end
end
