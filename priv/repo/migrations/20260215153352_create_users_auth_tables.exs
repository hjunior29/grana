defmodule Grana.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    email_type = if repo().__adapter__() == Ecto.Adapters.Postgres, do: :citext, else: :string

    if repo().__adapter__() == Ecto.Adapters.Postgres do
      execute "CREATE EXTENSION IF NOT EXISTS citext", ""
    end

    email_opts =
      if repo().__adapter__() == Ecto.Adapters.Postgres do
        [null: false]
      else
        [null: false, collate: :nocase]
      end

    create table(:users) do
      add :email, email_type, email_opts
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
