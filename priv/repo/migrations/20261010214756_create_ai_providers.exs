defmodule Grana.Repo.Migrations.CreateAiProviders do
  use Ecto.Migration

  def up do
    create table(:ai_providers) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :name, :string, null: false
      add :base_url, :string
      add :api_key, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_providers, [:user_id, :name])

    flush()

    # A chave única que ficava no usuário vira o primeiro provedor cadastrado (o valor
    # cifrado é copiado como está, pois a chave de criptografia é a mesma).
    %{rows: rows} =
      repo().query!("SELECT id, ai_api_key FROM users WHERE ai_api_key IS NOT NULL")

    for [user_id, api_key] <- rows do
      %{rows: [[provider_id]]} =
        repo().query!(
          "INSERT INTO ai_providers (user_id, kind, name, api_key, inserted_at, updated_at) VALUES (?, 'gemini', 'Google Gemini', ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id",
          [user_id, api_key]
        )

      repo().query!("UPDATE users SET ai_provider = ? WHERE id = ?", [
        "db:#{provider_id}",
        user_id
      ])
    end

    # Quem não tinha chave volta ao estado "sem padrão" (o default antigo era "gemini").
    repo().query!(
      "UPDATE users SET ai_provider = NULL, ai_model = NULL WHERE ai_provider = 'gemini'"
    )

    alter table(:users) do
      remove :ai_api_key
    end
  end

  def down do
    alter table(:users) do
      add :ai_api_key, :string
    end

    drop table(:ai_providers)
  end
end
