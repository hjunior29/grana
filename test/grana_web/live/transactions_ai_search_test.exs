defmodule GranaWeb.TransactionsAiSearchTest do
  use GranaWeb.ConnCase, async: false
  use Mimic

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures

  alias Grana.LLMStub

  setup :register_and_log_in_user
  setup :set_mimic_global

  setup %{user: user} do
    stub(Grana.AI.Models, :list, fn _config ->
      {:ok, [%{id: "gemini-pro", name: "Gemini Pro"}]}
    end)

    %{user: ai_fixture(user)}
  end

  defp advanced(conn) do
    {:ok, view, _html} = live(conn, ~p"/transactions?mode=advanced")
    render_async(view)
    view
  end

  defp ask(view, request, model \\ "") do
    view |> form("#ai-search-form", %{"request" => request, "model" => model}) |> render_submit()
    render_async(view)
  end

  test "the box sits in the advanced search with the search specialist default", %{conn: conn} do
    view = advanced(conn)

    assert has_element?(view, "#advanced-search #ai-search-form #ai-search-request")
    assert has_element?(view, "#ai-search-model option", "Padrão · gemini-test-model")
  end

  test "a ready query comes back as a chip that fills the search field", %{conn: conn} do
    LLMStub.script([
      {:tool, "submit_query",
       %{"query" => "uber AND type:expense", "explanation" => "Gastos com Uber."}}
    ])

    view = advanced(conn)
    ask(view, "gastos com uber")

    assert has_element?(view, "#ai-search-result code", "uber AND type:expense")
    assert has_element?(view, "#ai-search-result", "Gastos com Uber.")
    assert has_element?(view, "#ai-search-result", "gemini-test-model")

    [click] =
      view
      |> element("#ai-search-use")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("phx-click")

    assert click =~ "grana:use-query"
    assert click =~ "#advanced-search-query"
    assert click =~ "uber AND type:expense"

    assert has_element?(view, "#ai-search-request[value='gastos com uber']")
  end

  test "a request that is not a search gets a short text", %{conn: conn} do
    LLMStub.script(["Eu monto buscas de transações; descreva o que procura."])

    view = advanced(conn)
    ask(view, "oi")

    assert has_element?(view, "#ai-search-text", "Eu monto buscas")

    view |> element("#ai-search-text button") |> render_click()
    refute has_element?(view, "#ai-search-text")
  end

  test "the model picked for the request is used", %{conn: conn, user: user} do
    agent = LLMStub.script(["ok"])
    [ref, _model] = user |> Grana.AI.general_choice() |> String.split("|")

    view = advanced(conn)
    ask(view, "x", Grana.AI.choice(ref, "gemini-pro"))

    assert [{%{model: "gemini-pro"}, _messages}] = LLMStub.calls(agent)
  end

  test "errors show up below the box", %{conn: conn} do
    LLMStub.script([{:error, "boom"}])

    view = advanced(conn)
    ask(view, "uber")

    assert has_element?(view, "#ai-search-error", "A IA respondeu com erro: boom")
  end

  test "without a provider it points to the settings", %{conn: conn} do
    Grana.Repo.delete_all(Grana.AI.ProviderConfig)

    view = advanced(conn)
    ask(view, "uber")

    assert has_element?(view, "#ai-search-error", "Cadastre um provedor de IA")
  end

  test "a blank request does nothing", %{conn: conn} do
    view = advanced(conn)
    ask(view, "   ")

    refute has_element?(view, "#ai-search-loading")
    refute has_element?(view, "#ai-search-error")
  end
end
