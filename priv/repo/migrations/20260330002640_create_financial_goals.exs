defmodule Grana.Repo.Migrations.CreateFinancialGoals do
  use Ecto.Migration

  def change do
    create table(:financial_goals) do
      add :type, :string, null: false
      add :target_value, :decimal, null: false
      add :active, :boolean, default: true, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :category_id, references(:categories, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:financial_goals, [:user_id])

    create unique_index(:financial_goals, [:user_id, :type],
             where: "category_id IS NULL AND active = true",
             name: :financial_goals_user_type_active_idx
           )

    create unique_index(:financial_goals, [:user_id, :type, :category_id],
             where: "category_id IS NOT NULL AND active = true",
             name: :financial_goals_user_type_category_active_idx
           )
  end
end
