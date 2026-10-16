defmodule GranaWeb.LandingLiveTest do
  use GranaWeb.ConnCase

  setup :ensure_owner

  import Phoenix.LiveViewTest

  test "a história da logo é a primeira seção e segue intacta", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert has_element?(lv, "#logo-story[phx-hook][data-geometry]")
    assert :binary.match(html, ~s(id="logo-story")) < :binary.match(html, ~s(id="hero"))

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

    for cat <- GranaWeb.BrandComponents.geometry().categories do
      assert has_element?(lv, "#logo-story-categories li", cat.name)
    end

    assert has_element?(lv, ~s|#logo-story-final svg[aria-label="Grana"]|)
  end

  test "o manifesto explica o self-hosted e tem Entrar e Instalar", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert has_element?(lv, "#hero[data-motion]")
    assert has_element?(lv, ~s|#hero-login[href="/users/log-in"]|)
    assert has_element?(lv, ~s|#hero-install[href="#instalacao"]|)
    assert html =~ "no seu servidor"
    assert has_element?(lv, "#hero .lp-facts li", "Um arquivo SQLite")
  end

  test "a marca é o símbolo com o nome em vetor, no topo e no rodapé", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    for id <- ~w(landing-brand footer-brand) do
      assert has_element?(lv, ~s|##{id} img[src^="/images/logo"]|)
      assert has_element?(lv, ~s|##{id} svg[aria-label="Grana"]|)
    end
  end

  test "o motion pela rolagem cobre as seções e as cenas", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert has_element?(lv, "#lp[phx-hook]")

    for id <- ~w(hero como-funciona painel open-finance privacidade seguranca instalacao cta) do
      assert has_element?(lv, "##{id}[data-motion]"), "faltou ##{id}"
    end

    for id <- ~w(importacao categorias ia) do
      assert has_element?(lv, "##{id}[data-scene] .lp-stage"), "faltou a cena ##{id}"
    end

    document = LazyHTML.from_document(html)
    assert document |> LazyHTML.query(".lp-rise") |> Enum.count() > 20
    assert document |> LazyHTML.query(".lp-t") |> Enum.count() > 30
  end

  test "mostra as funcionalidades de hoje", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert has_element?(lv, "#importacao", "Solte os arquivos e siga a vida")
    assert has_element?(lv, "#importacao .lp-file", "fatura-itau.pdf")
    assert has_element?(lv, "#importacao .lp-toast", "Importação concluída")

    assert has_element?(lv, "#categorias", "Cada transação no seu lugar")
    assert has_element?(lv, "#categorias .lp-cat-chip", "Unimed") == false
    assert has_element?(lv, "#categorias .lp-cat-chip", "Saúde")

    assert has_element?(lv, "#painel", "O mês inteiro numa tela")
    assert has_element?(lv, "#painel #landing-cat-hook[data-categories]")
    assert has_element?(lv, "#painel #landing-flow-hook[data-flow]")
    assert has_element?(lv, "#painel .lp-heat .ui-heat-cell.ui-heat-spend")
    assert has_element?(lv, "#painel", "Despesas fixas")
    assert has_element?(lv, "#painel", "Parcelas")

    for text <- [
          "Descreva a busca em português",
          "Nota, resumo e dicas do mês",
          "PDFs que nenhum parser conhece",
          "Converse com os seus números"
        ] do
      assert has_element?(lv, "#ia .lp-panel", text)
    end

    assert has_element?(lv, "#ia .ui-chat-step-agent", "Especialista de pesquisa")
    assert has_element?(lv, "#ia .ui-score", "8.2")

    assert html =~ "Open Finance"
    assert has_element?(lv, "#open-finance-preview", "Hoje")
    assert has_element?(lv, "#privacidade", "Modo privacidade")
    assert has_element?(lv, "#privacidade .lp-swatches li", "Cyber")
    assert has_element?(lv, "#seguranca", "2FA por email")
    assert has_element?(lv, "#seguranca", "Backup e restauração")
    refute html =~ "Roadmap"
  end

  test "a instalação tem os três passos e o README", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    for n <- 1..3, do: assert(has_element?(lv, "#instalacao-passo-#{n}"))
    assert has_element?(lv, "#instalacao-readme")
    assert has_element?(lv, "#instalacao", "docker compose up -d")
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
