defmodule Grana.Repo.Migrations.EncryptAiApiKeys do
  use Ecto.Migration

  def up do
    # Clear existing plaintext API keys.
    # Users will need to re-enter their keys, which will then be stored encrypted.
    execute("UPDATE users SET ai_api_key = NULL WHERE ai_api_key IS NOT NULL")
  end

  def down do
    # Cannot restore plaintext keys; this is a one-way migration.
    :ok
  end
end
