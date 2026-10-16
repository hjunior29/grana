defmodule Grana.Repo.Migrations.AddAiModelToBankStatements do
  use Ecto.Migration

  def change do
    alter table(:bank_statements) do
      add :ai_provider, :string
      add :ai_model, :string
    end
  end
end
