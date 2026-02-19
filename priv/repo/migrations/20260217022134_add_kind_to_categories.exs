defmodule Grana.Repo.Migrations.AddKindToCategories do
  use Ecto.Migration

  def change do
    alter table(:categories) do
      add :kind, :string, default: "expense", null: false
    end

    create index(:categories, [:kind])

    # Set correct kinds for existing categories
    flush()

    execute(
      "UPDATE categories SET kind = 'investment' WHERE name = 'Investimentos'",
      "UPDATE categories SET kind = 'expense' WHERE name = 'Investimentos'"
    )

    execute(
      "UPDATE categories SET kind = 'income' WHERE name IN ('Rendimentos', 'Salário')",
      "UPDATE categories SET kind = 'expense' WHERE name IN ('Rendimentos', 'Salário')"
    )
  end
end
