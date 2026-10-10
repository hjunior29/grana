defmodule GranaWeb.LandingLiveTest do
  use GranaWeb.ConnCase

  setup :ensure_owner

  import Phoenix.LiveViewTest

  test "renders landing page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Controle total"
    assert html =~ "suas finanças"
    assert html =~ "Entrar"
    refute html =~ "Criar Conta"
    refute html =~ "/users/register"
    refute html =~ "/terms"
    refute html =~ "oadmap"
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

  test "dono logado é levado direto ao painel", %{conn: conn} do
    conn = log_in_user(conn, Grana.AccountsFixtures.user_fixture())
    assert {:error, {:live_redirect, %{to: "/dashboard"}}} = live(conn, ~p"/")
  end
end
