defmodule GranaWeb.DashboardAnalysisTest do
  use GranaWeb.ConnCase, async: false
  use Mimic

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Analyses
  alias Grana.LLMStub

  setup :register_and_log_in_user
  setup :set_mimic_global

  setup %{user: user} do
    stub(Grana.AI.Models, :list, fn _config ->
      {:ok, [%{id: "gemini-pro", name: "Gemini Pro"}]}
    end)

    user = ai_fixture(user)
    transaction_fixture(user, %{description: "MERCADO", amount: "-80.00", date: ~D[2026-03-10]})
    transaction_fixture(user, %{description: "UBER", amount: "-30.00", date: ~D[2026-02-05]})
    Analyses.subscribe(user.id)

    on_exit(fn ->
      Analyses.clear(user.id, 2026, 3)
      Analyses.clear(user.id, 2026, 2)
      Analyses.clear(user.id, 2026, 0)
    end)

    %{user: user}
  end

  defp answer(title) do
    Jason.encode!(%{
      "nota" => 8.2,
      "titulo" => title,
      "resumo" => "Sobrou dinheiro.",
      "pontos" => [%{"tipo" => "dica", "texto" => "Reduza o delivery."}],
      "alerta" => "Parcelas altas."
    })
  end

  defp await_analysis(view, month \\ 3) do
    assert_receive {:agent_run, {:analysis, 2026, ^month}, _event}, 5_000
    render(view)
  end

  test "the panel sits below the filters, closed, with the button and the model", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")
    render_async(view)

    html = render(view)
    assert has_element?(view, "#banking-filters")

    assert :binary.match(html, ~s(id="analysis-panel")) <
             :binary.match(html, ~s(id="stat-income"))

    assert has_element?(view, "#analysis-toggle[aria-expanded=false]", "Análise de março de 2026")
    assert has_element?(view, "#analysis-empty")
    assert has_element?(view, "#analyze-button", "Analisar com IA")
    assert has_element?(view, "#analysis-model option", "Padrão · gemini-test-model")
    refute has_element?(view, "#analysis-score")
  end

  test "opening the panel is remembered", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view |> element("#analysis-toggle") |> render_click()
    assert has_element?(view, "#analysis-toggle[aria-expanded=true]")
    assert Grana.Accounts.get_user!(user.id).analysis_open

    {:ok, again, _html} = live(conn, ~p"/dashboard")
    assert has_element?(again, "#analysis-toggle[aria-expanded=true]")

    again |> element("#analysis-toggle") |> render_click()
    assert has_element?(again, "#analysis-toggle[aria-expanded=false]")
  end

  test "analyzing shows the result and survives leaving the screen", %{conn: conn, user: user} do
    test_pid = self()

    LLMStub.script([
      fn _messages ->
        send(test_pid, {:waiting, self()})

        receive do
          :go -> answer("Março tranquilo")
        end
      end
    ])

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    view |> form("#analysis-form") |> render_submit()
    assert_receive {:waiting, task}, 5_000

    assert has_element?(view, "#analysis-loading")
    assert has_element?(view, "#analyze-button[disabled]")
    assert has_element?(view, "#analysis-model[disabled]")

    # Away and back: still analyzing. Elsewhere: the notice when it ends.
    {:ok, other, _html} = live(conn, ~p"/goals")
    {:ok, back, _html} = live(conn, ~p"/dashboard")
    assert has_element?(back, "#analysis-loading")

    send(task, :go)
    await_analysis(back)

    assert has_element?(back, "#analysis-score", "8.2")
    assert has_element?(back, "#analysis-content", "Março tranquilo")
    assert has_element?(back, "#analysis-content", "Reduza o delivery.")
    assert has_element?(back, "#analysis-content", "Parcelas altas.")
    assert has_element?(back, "#analysis-toggle", "gemini-test-model")
    assert has_element?(back, "#analyze-button", "Analisar de novo")
    refute has_element?(back, "#ai-toast")

    assert has_element?(other, "#ai-toast", "Análise pronta")
    assert has_element?(other, ~s|#ai-toast-open[href="/dashboard?month=3&year=2026"]|)
    assert %{ai_model: "gemini-test-model"} = Analyses.latest(user.id, 2026, 3)
  end

  test "the notice link opens the analyzed period", %{conn: conn, user: user} do
    LLMStub.script([answer("Ano todo")])
    {:ok, :started} = Analyses.request(user.id, 2026, 0)
    assert_receive {:agent_run, {:analysis, 2026, 0}, {:done, _}}, 5_000

    {:ok, view, _html} = live(conn, ~p"/dashboard?year=2026&month=all")
    assert has_element?(view, "#analysis-toggle", "Análise de 2026")
    assert has_element?(view, "#analysis-content", "Ano todo")
  end

  test "the panel follows the period filter", %{conn: conn, user: user} do
    LLMStub.script([answer("Março tranquilo")])
    {:ok, :started} = Analyses.request(user.id, 2026, 3)
    assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, _}}, 5_000

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    assert has_element?(view, "#analysis-content", "Março tranquilo")

    render_click(view, "select_month", %{"month" => "2"})
    assert has_element?(view, "#analysis-toggle", "Análise de fevereiro de 2026")
    assert has_element?(view, "#analysis-empty")

    render_click(view, "select_month", %{"month" => "all"})
    assert has_element?(view, "#analysis-toggle", "Análise de 2026")

    render_click(view, "select_view_total", %{})
    refute has_element?(view, "#analysis-panel")
  end

  test "nothing new since the last analysis keeps it without another request", %{
    conn: conn,
    user: user
  } do
    LLMStub.script([answer("Março tranquilo")])
    {:ok, :started} = Analyses.request(user.id, 2026, 3)
    assert_receive {:agent_run, {:analysis, 2026, 3}, {:done, _}}, 5_000

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    view |> form("#analysis-form") |> render_submit()

    assert has_element?(view, "#analysis-current")
    assert has_element?(view, "#analysis-content", "Março tranquilo")
    refute_receive {:agent_run, _, _}, 100
  end

  test "other filters show a note that the analysis ignores them", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")
    refute has_element?(view, "#analysis-filters-note")

    render_click(view, "select_bank", %{"bank" => "nubank"})
    assert has_element?(view, "#analysis-filters-note", "sem os filtros de banco, fonte e tipo")
  end

  test "a failed analysis shows the error on the panel and notifies elsewhere", %{
    conn: conn,
    user: user
  } do
    LLMStub.script([{:error, "boom"}, {:error, "boom"}])
    {:ok, other, _html} = live(conn, ~p"/goals")

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    view |> form("#analysis-form") |> render_submit()
    await_analysis(view)

    assert has_element?(view, "#analysis-error", "A IA respondeu com erro: boom")
    assert has_element?(other, "#ai-toast", "A IA não conseguiu analisar o período")
    assert %{outcome: {:error, _}} = Analyses.in_progress(user.id, 2026, 3)
  end

  test "without a provider it points to the settings", %{conn: conn} do
    Grana.Repo.delete_all(Grana.AI.ProviderConfig)

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    view |> form("#analysis-form") |> render_submit()
    await_analysis(view)

    assert has_element?(view, "#analysis-error", "Cadastre um provedor de IA")
  end

  test "the old analysis screen is gone", %{conn: conn} do
    assert conn |> get("/analysis") |> response(404)
    {:ok, _view, html} = live(conn, ~p"/dashboard")
    refute html =~ ~s|href="/analysis"|
  end
end
