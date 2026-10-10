defmodule Grana.Repo.Migrations.AddSmtpAndTwoFactor do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :smtp_host, :string
      add :smtp_port, :integer
      add :smtp_username, :string
      add :smtp_password, :string
      add :smtp_tls, :string
      add :smtp_from_name, :string
      add :smtp_from_address, :string
      add :inactivity_reminded_at, :utc_datetime
    end

    alter table(:users_tokens) do
      add :attempts, :integer, null: false, default: 0
    end
  end
end
