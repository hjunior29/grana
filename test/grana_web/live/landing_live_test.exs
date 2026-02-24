defmodule GranaWeb.LandingLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders landing page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Controle total"
    assert html =~ "suas finanças"
    assert html =~ "Criar Conta"
    assert html =~ "Entrar"
  end

  test "shows features section", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Upload Simples"
    assert html =~ "Categorização Inteligente"
    assert html =~ "Gráficos Detalhados"
  end

  test "shows how it works section", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Como funciona"
    assert html =~ "Faça Upload"
    assert html =~ "Processamento Automático"
  end
end
