defmodule Custo.Repo do
  use Ecto.Repo,
    otp_app: :custo,
    adapter: Ecto.Adapters.Postgres
end
