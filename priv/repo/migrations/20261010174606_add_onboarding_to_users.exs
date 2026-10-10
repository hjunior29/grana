defmodule Grana.Repo.Migrations.AddOnboardingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :onboarded_at, :utc_datetime
      add :base_url, :string
    end

    # Quem já usa o app não passa pelo onboarding.
    execute "UPDATE users SET onboarded_at = CURRENT_TIMESTAMP", ""
  end
end
