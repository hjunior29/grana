defmodule Grana.Repo.Migrations.AddIdentityToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Nome e CPF do titular, usados para reconhecer transferências entre as
      # próprias contas (a contraparte é o próprio usuário). CPF é criptografado
      # (Grana.Encrypted.Binary), como a ai_api_key.
      add :name, :string
      add :cpf, :binary
    end
  end
end
