defmodule GranaiWeb.PageController do
  use GranaiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
