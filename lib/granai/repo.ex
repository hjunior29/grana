defmodule Grana.Repo do
  use Ecto.Repo,
    otp_app: :grana,
    adapter: Ecto.Adapters.Postgres
end
