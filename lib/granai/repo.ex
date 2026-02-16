defmodule Granai.Repo do
  use Ecto.Repo,
    otp_app: :granai,
    adapter: Ecto.Adapters.Postgres
end
