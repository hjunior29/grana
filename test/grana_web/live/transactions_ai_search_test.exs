defmodule GranaWeb.TransactionsAiSearchTest do
  use GranaWeb.ConnCase, async: false
  use Mimic

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures

  alias Grana.Agents.Run
  alias Grana.LLMStub

  setup :register_and_log_in_user
  setup :set_mimic_global

  setup %{user: user} do
    stub(Grana.AI.Models, :list, fn _config ->
      {:ok, [%{id: "gemini-pro", name: "Gemini Pro"}]}
    end)

    on_exit(fn -> Run.clear(user.id, :search) end)
    Run.subscribe(user.id)
    %{user: ai_fixture(user)}
  end

  defp advanced(conn) do
    {:ok, view, _html} = live(conn, ~p"/transactions?mode=advanced")
    render_async(view)
    view
  end

  defp ask(view, request, model \\ "") do
    view |> form("#ai-search-form", %{"request" => request, "model" => model}) |> render_submit()
    render(view)
  end

  defp await_build(view) do
    assert_receive {:agent_run, :search, _event}, 5_000
    render(view)
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
    await_build(view)

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

  test "a request that is not a search gets a short text", %{conn: conn, user: user} do
    LLMStub.script(["Eu monto buscas de transações; descreva o que procura."])

    view = advanced(conn)
    ask(view, "oi")
    await_build(view)

    assert has_element?(view, "#ai-search-text", "Eu monto buscas")

    view |> element("#ai-search-text button") |> render_click()
    refute has_element?(view, "#ai-search-text")
    assert Run.current(user.id, :search) == nil
  end

  test "the model picked for the request is used", %{conn: conn, user: user} do
    agent = LLMStub.script(["ok"])
    [ref, _model] = user |> Grana.AI.general_choice() |> String.split("|")

    view = advanced(conn)
    ask(view, "x", Grana.AI.choice(ref, "gemini-pro"))
    await_build(view)

    assert [{%{model: "gemini-pro"}, _messages}] = LLMStub.calls(agent)
  end

  test "errors show up below the box", %{conn: conn} do
    LLMStub.script([{:error, "boom"}])

    view = advanced(conn)
    ask(view, "uber")
    await_build(view)

    assert has_element?(view, "#ai-search-error", "A IA respondeu com erro: boom")
  end

  test "without a provider it points to the settings", %{conn: conn} do
    Grana.Repo.delete_all(Grana.AI.ProviderConfig)

    view = advanced(conn)
    ask(view, "uber")
    await_build(view)

    assert has_element?(view, "#ai-search-error", "Cadastre um provedor de IA")
  end

  test "a blank request does nothing", %{conn: conn} do
    view = advanced(conn)
    ask(view, "   ")

    refute has_element?(view, "#ai-search-loading")
    refute has_element?(view, "#ai-search-error")
  end

  test "while building, the box is locked and survives leaving the screen", %{
    conn: conn,
    user: user
  } do
    test_pid = self()

    LLMStub.script([
      fn _messages ->
        send(test_pid, {:waiting, self()})

        receive do
          :go -> {:tool, "submit_query", %{"query" => "unimed", "explanation" => "Saúde."}}
        end
      end
    ])

    view = advanced(conn)
    ask(view, "gastos com saúde")
    assert_receive {:waiting, task}, 5_000

    assert has_element?(view, "#ai-search-loading")
    assert has_element?(view, "#ai-search-request[disabled]")
    assert has_element?(view, "#ai-search-model[disabled]")
    assert has_element?(view, "#ai-search-submit[disabled]")

    # Away and back: still building, with the same request on the field.
    {:ok, other, _html} = live(conn, ~p"/dashboard")
    back = advanced(conn)
    assert has_element?(back, "#ai-search-loading")
    assert has_element?(back, "#ai-search-request[disabled][value='gastos com saúde']")

    send(task, :go)
    await_build(back)
    assert has_element?(back, "#ai-search-result code", "unimed")
    refute has_element?(back, "#ai-search-request[disabled]")
    refute has_element?(back, "#ai-toast")

    # The screen that was not looking got the notice, with a link to the search.
    assert has_element?(other, "#ai-toast", "Busca pronta")
    assert has_element?(other, ~s|#ai-toast-open[href="/transactions?mode=advanced"]|)
    other |> element("#ai-toast-close") |> render_click()
    refute has_element?(other, "#ai-toast")

    # The result waits for the user to come back to the screen.
    again = advanced(conn)
    assert has_element?(again, "#ai-search-result code", "unimed")
    assert %{input: "gastos com saúde"} = Run.current(user.id, :search)
  end

  test "a failed build also notifies the other screens", %{conn: conn, user: user} do
    LLMStub.script([{:error, "boom"}])
    {:ok, other, _html} = live(conn, ~p"/dashboard")

    {:ok, _pid} =
      Run.start(user.id, :search, "uber", fn ->
        Grana.Agents.SearchBuilder.run(user.id, "uber")
      end)

    assert_receive {:agent_run, :search, {:error, _}}, 5_000

    assert has_element?(other, "#ai-toast", "A IA não conseguiu montar a busca")
    assert has_element?(other, "#ai-toast-open", "Ver busca")
  end
end
