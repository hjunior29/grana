defmodule Grana.Repo.Migrations.MakeCategoriesUserIdNonNullable do
  use Ecto.Migration

  def up do
    execute "DELETE FROM categories WHERE user_id IS NULL"

    if repo().__adapter__() == Ecto.Adapters.Postgres do
      alter table(:categories) do
        modify :user_id, references(:users, on_delete: :delete_all),
          null: false,
          from: references(:users, on_delete: :delete_all)
      end
    end
  end

  def down do
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      alter table(:categories) do
        modify :user_id, references(:users, on_delete: :delete_all),
          null: true,
          from: references(:users, on_delete: :delete_all)
      end
    end
  end
end
