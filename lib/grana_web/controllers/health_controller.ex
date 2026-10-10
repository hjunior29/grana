defmodule GranaWeb.HealthController do
  use GranaWeb, :controller

  def show(conn, _params) do
    Grana.Repo.query!("SELECT 1")
    json(conn, %{status: "ok"})
  end
end
