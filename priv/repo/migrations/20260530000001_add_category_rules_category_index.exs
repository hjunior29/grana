defmodule Grana.Repo.Migrations.AddCategoryRulesCategoryIndex do
  use Ecto.Migration

  def change do
    # FK category_rules.category_id had no index: cascade deletes and joins on it
    # forced a sequential scan. Index it.
    create_if_not_exists index(:category_rules, [:category_id])
  end
end
