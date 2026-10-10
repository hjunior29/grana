defmodule GranaWeb.LandingLiveTest do
  use GranaWeb.ConnCase

  setup :ensure_owner

  import Phoenix.LiveViewTest

  test "o hero explica o self-hosted e tem Entrar e Instalar", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert has_element?(lv, "#hero")
    assert has_element?(lv, ~s|#hero-login[href="/users/log-in"]|)
    assert has_element?(lv, ~s|#hero-install[href="#instalacao"]|)
    assert html =~ "no seu servidor"
  end

  test "a marca é o símbolo com o nome em vetor, no topo e no rodapé", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    for id <- ~w(landing-brand footer-brand) do
      assert has_element?(lv, ~s|##{id} img[src^="/images/logo"]|)
      assert has_element?(lv, ~s|##{id} svg[aria-label="Grana"]|)
    end

    assert has_element?(lv, ~s|#hero img[src^="/images/logo"]|)
  end

  test "a história da logo passa pela moeda, pelas categorias do sistema e pelos meses", %{
    conn: conn
  } do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, "#logo-story[phx-hook][data-geometry]")

    # Ordem da história: moeda, categorias, meses e o fechamento.
    for {id, step} <- [
          {"logo-story-coin", 0},
          {"logo-story-categories", 1},
          {"logo-story-months", 2},
          {"logo-story-final", 3}
        ] do
      assert has_element?(lv, ~s|##{id}[data-panel="#{step}"]|)
    end

    assert has_element?(lv, "#logo-story-categories", "R$ 6.400,00")
    assert has_element?(lv, "#logo-story-months", "Receitas vs Despesas")
    assert has_element?(lv, "#logo-story-months", "+R$ 16.600,00")
    assert has_element?(lv, "#logo-story-months", "economizou 18,4%")

    for cat <- GranaWeb.BrandComponents.geometry().categories do
      assert has_element?(lv, "#logo-story-categories li", cat.name)
    end

    assert has_element?(lv, ~s|#logo-story-final svg[aria-label="Grana"]|)
  end

  test "tem as seções de como funciona, Open Finance, segurança e instalação", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    for id <- ~w(como-funciona open-finance open-finance-preview seguranca instalacao features) do
      assert has_element?(lv, "##{id}"), "faltou ##{id}"
    end

    for n <- 1..3, do: assert(has_element?(lv, "#instalacao-passo-#{n}"))
    assert has_element?(lv, "#instalacao-readme")
  end

  test "mantém as seções de produto", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "Dashboard inteligente"
    assert html =~ "Análise com IA"
    assert html =~ "Cada transação no seu lugar"
  end

  test "as features incluem Open Finance, backup e 2FA e não o roadmap", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "Open Finance"
    assert html =~ "Backup e restauração"
    assert html =~ "Login com 2FA"
    refute html =~ "Roadmap"
  end

  test "o CTA Entrar aponta para o login e nada leva a cadastro ou termos", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert has_element?(lv, ~s|#cta-login[href="/users/log-in"]|)
    refute html =~ "/users/register"
    refute html =~ "/terms"
    refute html =~ "Criar Conta"
    refute html =~ "Crie sua conta"
  end

  test "o footer aponta para o repositório", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, ~s|#footer-github[href="https://github.com/hjunior29/grana"]|)
  end

  test "dono logado é levado direto ao painel", %{conn: conn} do
    conn = log_in_user(conn, Grana.AccountsFixtures.user_fixture())
    assert {:error, {:live_redirect, %{to: "/dashboard"}}} = live(conn, ~p"/")
  end
end
