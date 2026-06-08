defmodule GranaWeb.TermsLiveTest do
  use GranaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders terms page" do
    {:ok, _view, html} = live(build_conn(), ~p"/terms")
    assert html =~ "Termos de Uso"
    assert html =~ "Grana"
  end

  test "page title is set" do
    {:ok, view, _html} = live(build_conn(), ~p"/terms")
    assert page_title(view) =~ "Termos"
  end

  test "shows login and register links for unauthenticated user" do
    {:ok, _view, html} = live(build_conn(), ~p"/terms")
    assert html =~ "Entrar"
  end
end
