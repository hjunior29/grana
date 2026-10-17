defmodule GranaWeb.LandingLiveTest do
  use GranaWeb.ConnCase

  setup :ensure_owner

  import Phoenix.LiveViewTest

  test "the logo story is the first section and stays as it was", %{conn: conn} do
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

  test "the manifesto explains self-hosting and offers to log in or install", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert has_element?(lv, "#hero[data-motion]")
    assert has_element?(lv, ~s|#hero-login[href="/users/log-in"]|)
    assert has_element?(lv, ~s|#hero-install[href="#instalacao"]|)
    assert html =~ "no seu servidor"
    assert has_element?(lv, "#hero .lp-facts li", "Um arquivo SQLite")
  end

  test "the brand is the symbol with the vector name, on top and in the footer", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    for id <- ~w(landing-brand footer-brand) do
      assert has_element?(lv, ~s|##{id} img[src^="/images/logo"]|)
      assert has_element?(lv, ~s|##{id} svg[aria-label="Grana"]|)
    end
  end

  test "scroll motion covers the sections and the scenes", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert has_element?(lv, "#lp[phx-hook]")

    for id <- ~w(hero painel privacidade instalacao cta) do
      assert has_element?(lv, "##{id}[data-motion]"), "missing ##{id}"
    end

    for id <- ~w(como-funciona importacao categorias ia open-finance seguranca) do
      assert has_element?(lv, "##{id}[data-scene] .lp-stage"), "missing the ##{id} scene"
    end

    document = LazyHTML.from_document(html)
    assert document |> LazyHTML.query(".lp-rise") |> Enum.count() > 20
    assert document |> LazyHTML.query(".lp-t") |> Enum.count() > 50
  end

  test "shows today's features", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, "#importacao", "Solte os arquivos e siga a vida")
    assert has_element?(lv, "#importacao .lp-file", "fatura-itau.pdf")
    assert has_element?(lv, "#importacao .lp-toast", "Importação concluída")

    assert has_element?(lv, "#categorias", "Cada transação no seu lugar")
    refute has_element?(lv, "#categorias .lp-cat-chip", "Unimed")
    assert has_element?(lv, "#categorias .lp-cat-chip", "Saúde")

    assert has_element?(lv, "#painel", "O mês inteiro numa tela")
    assert has_element?(lv, "#painel #landing-cat-hook[data-categories]")
    assert has_element?(lv, "#painel #landing-flow-hook[data-flow]")
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
    refute render(lv) =~ "Roadmap"
  end

  test "the daily spending is the dashboard's calendar, and switches to bars", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    # March 2026: 31 days, three without spending, starting on a Sunday.
    assert has_element?(lv, "#landing-daily-view-calendar[aria-pressed=true]")
    assert has_element?(lv, "#landing-spending-calendar[phx-hook=SpendingCalendar]")

    calendar = lv |> element("#landing-spending-calendar") |> render() |> LazyHTML.from_fragment()
    assert calendar |> LazyHTML.query(".ui-heat-spend") |> Enum.count() == 28
    assert calendar |> LazyHTML.query(".ui-heat-empty") |> Enum.count() == 3

    captions = calendar |> LazyHTML.query(".ui-heat-caption") |> Enum.map(&LazyHTML.text/1)
    assert captions == Enum.map(1..31, &to_string/1)

    assert has_element?(lv, ~s|#landing-spending-calendar [data-day-date="01/03/2026"]|)
    refute has_element?(lv, "#landing-spending-calendar [data-day-url]")

    lv |> element("#landing-daily-view-bars") |> render_click()

    refute has_element?(lv, "#landing-spending-calendar")
    assert has_element?(lv, "#landing-daily-view-bars[aria-pressed=true]")

    daily =
      lv
      |> element("#landing-daily-chart[phx-hook=DailyChart]")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("data-daily")
      |> hd()
      |> Jason.decode!()

    assert length(daily) == 28
    assert daily |> Enum.map(& &1["value"]) |> Enum.sum() |> Float.round(2) == 4987.0

    lv |> element("#landing-daily-view-calendar") |> render_click()
    assert has_element?(lv, "#landing-spending-calendar")
  end

  test "the search mock types the request, then loads like the app", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, "#ia .lp-ai-search[style*='--ba'] .ui-ai-search-bar")
    assert has_element?(lv, "#ia .lp-ai-input .lp-typer-text", "gastos com saúde")
    assert has_element?(lv, "#ia .lp-ai-input .lp-ai-placeholder", "Peça à IA")
    assert has_element?(lv, "#ia .lp-ai-loading .loading-spinner")
    assert has_element?(lv, "#ia .lp-ai-loading", "Montando a busca…")
    assert has_element?(lv, "#ia .ui-ai-search-result .ui-query-code", "type:expense")
  end

  test "Open Finance shows the Pluggy connection, the data path and Hoje", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, "#open-finance", "Seus bancos, conectados pelo Open Finance")
    assert has_element?(lv, "#open-finance", "Do banco direto para o seu servidor")
    assert has_element?(lv, "#open-finance", "O retrato de hoje, sem esperar o extrato")

    assert has_element?(lv, ~s|#open-finance svg[aria-label="Open Finance Brasil"]|)
    assert has_element?(lv, ~s|#open-finance img[src^="/images/pluggy-logo"]|)
    assert has_element?(lv, "#open-finance", "Conectar via Meu Pluggy")
    assert has_element?(lv, "#open-finance .lp-of-widget .lp-of-perms", "Cartões e faturas")

    for node <- ["Seus bancos", "Open Finance Brasil", "Pluggy", "Seu Grana"] do
      assert has_element?(lv, "#open-finance .lp-of-node", node)
    end

    assert has_element?(lv, "#open-finance-preview", "Hoje")
    assert has_element?(lv, "#open-finance-preview #lp-today-card-available", "Limite disponível")
    assert has_element?(lv, "#open-finance-preview .ui-private", "R$ 1.180,40")

    assert has_element?(
             lv,
             "#open-finance-preview",
             "Meses sem upload cobertos pelo Open Finance"
           )
  end

  test "the privacy switches hide values and names on the whole page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, "#painel .ui-private", "R$ 9.650,00")
    assert has_element?(lv, "#lp-privacy .ui-private-name", "Pix Ana Souza")
    refute has_element?(lv, "#lp.ui-hide-values")
    refute has_element?(lv, "#lp.ui-hide-names")

    lv |> element("#lp-hide-values") |> render_click()
    assert has_element?(lv, "#lp.ui-hide-values")
    assert has_element?(lv, "#lp-hide-values[aria-checked=true]")
    refute has_element?(lv, "#lp.ui-hide-names")

    lv |> element("#lp-hide-names") |> render_click()
    assert has_element?(lv, "#lp.ui-hide-values.ui-hide-names")

    lv |> element("#lp-hide-values") |> render_click()
    refute has_element?(lv, "#lp.ui-hide-values")
    assert has_element?(lv, "#lp-hide-values[aria-checked=false]")
  end

  test "the visual styles are the app's own and restyle the page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, "#lp.grana-app-shell")

    for style <- ~w(default signal bossa papel caderneta planetario cyber) do
      assert has_element?(
               lv,
               ~s|#lp-styles #visual-style-toggle [data-phx-visual-style="#{style}"]|
             )
    end

    for theme <- ~w(system light dark) do
      assert has_element?(lv, ~s|#lp-styles [data-phx-theme="#{theme}"]|)
    end

    refute has_element?(lv, "#privacidade", "Metas")
  end

  test "the self-hosted scene tells where the data lives", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, "#seguranca", "Num app comum, seus dados moram com eles")
    assert has_element?(lv, "#seguranca", "No Grana, eles moram com você")
    assert has_element?(lv, "#seguranca .lp-sh-cloud", "Servidor de um app")
    assert has_element?(lv, "#seguranca .lp-sh-server", "grana.db")
    assert has_element?(lv, "#seguranca .lp-sh-ext", "Sua IA")
    assert has_element?(lv, "#seguranca .lp-sec-list", "2FA por email")
    assert has_element?(lv, "#seguranca .lp-sec-list", "Backup e restauração")
  end

  test "install has three steps, switches between script and Docker, and copies", %{
    conn: conn
  } do
    {:ok, lv, _html} = live(conn, ~p"/")

    for n <- 1..3, do: assert(has_element?(lv, "#instalacao-passo-#{n}[data-motion]"))
    assert has_element?(lv, "#instalacao[phx-hook]")
    assert has_element?(lv, "#instalacao-readme")
    assert has_element?(lv, "#install-method-script[aria-pressed=true]")
    assert has_element?(lv, "#instalacao-terminal-1", "bash install.sh")
    assert has_element?(lv, ~s|#instalacao-terminal-1 [data-copy*="deploy/install.sh"]|)
    assert has_element?(lv, "#instalacao-terminal-2", "journalctl -u grana")
    assert has_element?(lv, "#instalacao-terminal-2 .lp-term-code", "K7QF-2M9X")

    lv |> element("#install-method-docker") |> render_click()

    assert has_element?(lv, "#install-method-docker[aria-pressed=true]")
    assert has_element?(lv, "#instalacao-terminal-1", "docker compose up -d")
    assert has_element?(lv, ~s|#instalacao-terminal-1 [data-copy*="docker-compose.yml"]|)
    assert has_element?(lv, "#instalacao-terminal-2", "docker compose logs grana")
    refute has_element?(lv, "#instalacao-terminal-1", "bash install.sh")
  end

  test "the Entrar CTA goes to login and nothing leads to sign-up or terms", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert has_element?(lv, ~s|#cta-login[href="/users/log-in"]|)
    refute html =~ "/users/register"
    refute html =~ "/terms"
    refute html =~ "Criar Conta"
    refute html =~ "Crie sua conta"
  end

  test "the footer points to the repository", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, ~s|#footer-github[href="https://github.com/hjunior29/grana"]|)
  end

  test "a logged-in owner goes straight to the dashboard", %{conn: conn} do
    conn = log_in_user(conn, Grana.AccountsFixtures.user_fixture())
    assert {:error, {:live_redirect, %{to: "/dashboard"}}} = live(conn, ~p"/")
  end
end
