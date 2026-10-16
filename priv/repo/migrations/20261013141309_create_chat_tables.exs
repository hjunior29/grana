defmodule Grana.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  def change do
    create table(:chat_conversations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chat_conversations, [:user_id, :updated_at])

    create table(:chat_messages) do
      add :conversation_id, references(:chat_conversations, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :tool_calls, {:array, :map}, null: false, default: []
      add :ai_provider, :string
      add :ai_model, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:chat_messages, [:conversation_id, :id])
  end
end
