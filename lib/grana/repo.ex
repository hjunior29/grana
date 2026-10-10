defmodule Grana.Repo do
  use Ecto.Repo,
    otp_app: :grana,
    adapter: Ecto.Adapters.SQLite3
end
