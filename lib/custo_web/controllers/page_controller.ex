defmodule CustoWeb.PageController do
  use CustoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
