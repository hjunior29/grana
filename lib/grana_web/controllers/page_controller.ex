defmodule GranaWeb.PageController do
  use GranaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
