defmodule Grana.Repo.Migrations.AddPluggyCredentialsToUsers do
  use Ecto.Migration

  # Credenciais da Pluggy configuradas pela tela. O secret e o segredo do webhook
  # são gravados cifrados (Grana.Encrypted.Binary, AES-256-GCM com a CLOAK_KEY).
  def change do
    alter table(:users) do
      add :pluggy_client_id, :string
      add :pluggy_client_secret, :string
      add :pluggy_webhook_secret, :string
    end
  end
end
