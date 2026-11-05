defmodule GranaWeb.ChatLiveTest do
  use GranaWeb.ConnCase, async: false
  use Mimic

  import Phoenix.LiveViewTest
  import Grana.AccountsFixtures
  import Grana.BankingFixtures

  alias Grana.Chat
  alias Grana.LLMStub

  setup :register_and_log_in_user
  setup :set_mimic_global

  setup %{user: user} do
    stub(Grana.AI.Models, :list, fn _config ->
      {:ok, [%{id: "gemini-pro", name: "Gemini Pro"}]}
    end)

    transaction_fixture(user, %{description: "UBER TRIP", amount: "-30.00", date: ~D[2026-03-10]})
    Chat.subscribe(user.id)
    %{user: ai_fixture(user)}
  end

  # Answers run in the background: wait for the end of the answer before looking.
  defp await_reply(view) do
    assert_receive {:chat_reply, _id, {kind, _}} when kind in [:done, :error], 5_000
    render(view)
  end

  # The answer stays in the animated draft until the browser reports the animation is done.
  defp reveal(view), do: render_hook(view, "answer_revealed", %{})

  test "the chat link sits after Painel in the menu", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/chat")

    assert html =~ ~r/Painel<\/a>\s*<\/li>\s*<li>\s*<a[^>]*href="\/chat"/
  end

  test "starts with suggestions and the model picker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/chat")
    render_async(view)

    assert has_element?(view, "#chat-welcome")
    assert has_element?(view, "#chat-model option", "Padrão · gemini-test-model")
    assert has_element?(view, "#chat-model optgroup[label='Google Gemini'] option", "Gemini Pro")
    assert has_element?(view, "#conversations-empty")
  end

  test "sending a message answers with the tools used and the model", %{conn: conn, user: user} do
    LLMStub.script([
      {:tool, "get_period_summary", %{"year" => 2026, "month" => 3}},
      ~s|<p>Em março você gastou <strong>R$ 30,00</strong>.</p><script>alert(1)</script>| <>
        ~s|<table><tr><th>Item</th><th class="num">Valor</th></tr>| <>
        ~s|<tr><td>Uber</td><td class="num expense" onclick="x()">-R$ 30,00</td></tr></table>|
    ])

    {:ok, view, _html} = live(conn, ~p"/chat")
    render_async(view)

    view |> form("#chat-composer", %{"message" => "quanto gastei em março?"}) |> render_submit()

    assert has_element?(view, "#chat-messages .ui-chat-bubble", "quanto gastei em março?")
    await_reply(view)

    [conversation] = Chat.list_conversations(user.id)
    assert_patch(view, ~p"/chat/#{conversation.id}")

    assert has_element?(view, "#chat-draft[data-done=true] [data-source]", "Em março você gastou")
    refute has_element?(view, "#chat-messages .ui-chat-answer")
    reveal(view)

    assert has_element?(view, "#chat-messages .ui-chat-answer p strong", "R$ 30,00")
    assert has_element?(view, "#chat-messages .ui-chat-answer .ui-private", "R$ 30,00")

    assert has_element?(
             view,
             "#chat-messages .ui-chat-html table td.ui-num.ui-money-despesa",
             "-R$ 30,00"
           )

    refute has_element?(view, "#chat-messages script")
    refute has_element?(view, "#chat-messages [onclick]")
    assert has_element?(view, "#chat-messages .ui-chat-step-data", "Resumo do período")
    assert has_element?(view, "#chat-messages", "gemini-test-model")
    assert has_element?(view, "#conversations-#{conversation.id}", "quanto gastei em março?")
    refute has_element?(view, "#chat-pending")
  end

  test "a suggestion starts the conversation with the picked model", %{conn: conn, user: user} do
    agent = LLMStub.script(["Março foi tranquilo."])
    [ref, _model] = user |> Grana.AI.general_choice() |> String.split("|")

    {:ok, view, _html} = live(conn, ~p"/chat")
    render_async(view)

    view
    |> element("#chat-composer")
    |> render_change(%{"model" => Grana.AI.choice(ref, "gemini-pro")})

    view |> element("#chat-welcome button", "Analise o meu último mês") |> render_click()
    await_reply(view)
    reveal(view)

    assert has_element?(view, "#chat-messages", "Março foi tranquilo.")
    assert [{%{model: "gemini-pro"}, _messages}] = LLMStub.calls(agent)
  end

  test "a search built in the chat becomes a link to the transactions screen", %{conn: conn} do
    LLMStub.script([
      {:tool, "build_search", %{"request" => "uber"}},
      {:tool, "submit_query", %{"query" => "uber AND type:expense", "explanation" => "Uber."}},
      "Pronto, a busca está abaixo."
    ])

    {:ok, view, _html} = live(conn, ~p"/chat")
    view |> form("#chat-composer", %{"message" => "busca de uber"}) |> render_submit()
    await_reply(view)
    reveal(view)

    assert has_element?(
             view,
             ~s|#chat-messages a[href="/transactions?mode=advanced&q=uber+AND+type%3Aexpense"]|,
             "uber AND type:expense"
           )

    assert has_element?(view, "#chat-messages .ui-chat-step-agent", "Especialista de pesquisa")
  end

  test "the answer shows up while it is written", %{conn: conn, user: user} do
    test_pid = self()

    LLMStub.script([
      fn _messages ->
        send(test_pid, {:waiting, self()})

        receive do
          :go -> "Resposta final."
        end
      end
    ])

    {:ok, view, _html} = live(conn, ~p"/chat")
    view |> form("#chat-composer", %{"message" => "e março?"}) |> render_submit()
    assert_receive {:waiting, task}, 5_000
    [%{id: id}] = Chat.list_conversations(user.id)

    send(view.pid, {:chat_reply, id, {:delta, "<p>Em março "}})
    send(view.pid, {:chat_reply, id, {:delta, "você gastou R$ 30,00 <str"}})
    assert has_element?(view, "#chat-draft [data-source] p", "Em março você gastou R$ 30,00")
    assert has_element?(view, "#chat-draft .ui-private", "R$ 30,00")
    refute render(view) =~ "&lt;str"
    assert has_element?(view, "#chat-draft .ui-chat-caret")

    send(view.pid, {:chat_reply, id, {:tool, "get_period_summary"}})
    refute has_element?(view, "#chat-draft")
    assert has_element?(view, "#chat-pending .ui-chat-step", "Resumo do período")

    send(task, :go)
    await_reply(view)
    assert has_element?(view, "#chat-draft[data-done=true]", "Resposta final.")

    reveal(view)
    refute has_element?(view, "#chat-pending")
    assert has_element?(view, "#chat-messages .ui-chat-answer", "Resposta final.")
  end

  test "the answer is saved even if the browser never reports the animation", %{
    conn: conn,
    user: user
  } do
    LLMStub.script(["Tudo certo."])

    {:ok, view, _html} = live(conn, ~p"/chat")
    view |> form("#chat-composer", %{"message" => "oi"}) |> render_submit()
    await_reply(view)

    [conversation] = Chat.list_conversations(user.id)
    %{messages: [_question, answer]} = Chat.get_conversation(user.id, conversation.id)

    send(view.pid, {:flush_answer, answer.id + 1})
    refute has_element?(view, "#chat-messages .ui-chat-answer")

    send(view.pid, {:flush_answer, answer.id})
    assert has_element?(view, "#chat-messages .ui-chat-answer", "Tudo certo.")
    refute has_element?(view, "#chat-pending")

    reveal(view)
    assert has_element?(view, "#chat-messages .ui-chat-answer", "Tudo certo.")
  end

  test "an error can be retried without retyping", %{conn: conn} do
    LLMStub.script([{:error, "boom"}, {:error, "boom"}, "Agora foi."])

    {:ok, view, _html} = live(conn, ~p"/chat")
    view |> form("#chat-composer", %{"message" => "oi"}) |> render_submit()
    await_reply(view)

    assert has_element?(view, "#chat-error", "A IA respondeu com erro: boom")

    view |> element("#chat-retry") |> render_click()
    await_reply(view)
    reveal(view)

    refute has_element?(view, "#chat-error")
    assert has_element?(view, "#chat-messages", "Agora foi.")
  end

  test "opens, switches and deletes saved conversations", %{conn: conn, user: user} do
    {:ok, first} = Chat.start_conversation(user.id, "primeira")
    {:ok, _} = Chat.add_user_message(first, "primeira pergunta")
    {:ok, second} = Chat.start_conversation(user.id, "segunda")

    {:ok, view, _html} = live(conn, ~p"/chat/#{first.id}")

    assert has_element?(view, "#chat-messages", "primeira pergunta")
    assert has_element?(view, "#conversations-#{first.id}.ui-chat-conversation-active")

    view |> element("#conversations-#{second.id} a") |> render_click()
    assert_patch(view, ~p"/chat/#{second.id}")
    refute has_element?(view, "#chat-messages", "primeira pergunta")

    view |> element("#conversations-#{second.id} button") |> render_click()
    view |> element("#delete-conversation-modal button", "Apagar") |> render_click()
    # Without a conversation to show, /chat lands on the latest one left.
    assert_patch(view, ~p"/chat/#{first.id}")
    refute has_element?(view, "#conversations-#{second.id}")

    view |> element("#conversations-#{first.id} button") |> render_click()
    view |> element("#delete-conversation-modal button", "Apagar") |> render_click()
    refute has_element?(view, "#conversations-#{first.id}")
    assert Chat.list_conversations(user.id) == []
  end

  test "/chat opens the latest conversation; Nova conversa starts a blank one", %{
    conn: conn,
    user: user
  } do
    {:ok, _older} = Chat.start_conversation(user.id, "antiga")
    {:ok, latest} = Chat.start_conversation(user.id, "recente")

    # On the first load the patch becomes a redirect to the latest conversation.
    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/chat")
    assert to == "/chat/#{latest.id}"
    {:ok, view, _html} = live(conn, to)
    assert has_element?(view, "#conversations-#{latest.id}.ui-chat-conversation-active")

    view |> element("#new-conversation") |> render_click()
    assert_patch(view, ~p"/chat/new")
    assert has_element?(view, "#chat-welcome")
    refute has_element?(view, ".ui-chat-conversation-active")
  end

  test "a conversation of someone else or unknown sends back to a new one", %{conn: conn} do
    other = user_fixture()
    {:ok, foreign} = Chat.start_conversation(other.id, "dela")

    assert {:error,
            {:live_redirect, %{to: "/chat", flash: %{"error" => "Conversa não encontrada."}}}} =
             live(conn, ~p"/chat/#{foreign.id}")

    assert {:error, {:live_redirect, %{to: "/chat"}}} = live(conn, ~p"/chat/abc")
  end

  test "without a provider it asks to set one up", %{conn: conn, user: user} do
    Grana.Repo.delete_all(Grana.AI.ProviderConfig)

    {:ok, view, _html} = live(conn, ~p"/chat")
    view |> form("#chat-composer", %{"message" => "oi"}) |> render_submit()

    assert has_element?(view, "#ai-required-modal")
    assert Chat.list_conversations(user.id) == []

    render_click(view, "dismiss_api_alert")
    refute has_element?(view, "#ai-required-modal")
  end

  test "names from the user's transactions are marked for the privacy mode", %{
    conn: conn,
    user: user
  } do
    transaction_fixture(user, %{description: "Pagamento - UNIMED BH", amount: "-450.00"})
    LLMStub.script(["<p>A Unimed BH levou R$ 450,00.</p>"])

    {:ok, view, _html} = live(conn, ~p"/chat")
    view |> form("#chat-composer", %{"message" => "saúde?"}) |> render_submit()
    await_reply(view)
    reveal(view)

    assert has_element?(view, "#chat-messages .ui-chat-answer .ui-private-name", "Unimed BH")
    assert has_element?(view, "#chat-messages .ui-chat-answer .ui-private", "R$ 450,00")
  end

  test "leaving the chat mid-answer does not cancel it; coming back catches up", %{
    conn: conn,
    user: user
  } do
    test_pid = self()

    LLMStub.script([
      {:tool, "get_data_overview", %{}},
      fn _messages ->
        send(test_pid, {:waiting, self()})

        receive do
          :go -> "<p>Pronto.</p>"
        end
      end
    ])

    {:ok, view, _html} = live(conn, ~p"/chat")
    view |> form("#chat-composer", %{"message" => "oi"}) |> render_submit()
    assert_receive {:waiting, task}, 5_000
    [%{id: id}] = Chat.list_conversations(user.id)

    # Away: the answer keeps going. Back: the tools so far are on screen and no new
    # question can be sent for this conversation until it ends.
    {:ok, other, _html} = live(conn, ~p"/dashboard")
    {:ok, back, _html} = live(conn, ~p"/chat/#{id}")
    assert has_element?(back, "#chat-pending .ui-chat-step", "Visão geral dos dados")
    assert %{tools: ["get_data_overview"], draft: ""} = Chat.answer_in_progress(id)
    assert has_element?(back, "#chat-input[disabled]")

    send(task, :go)
    assert_receive {:chat_reply, ^id, {:done, _}}, 5_000
    reveal(back)
    assert has_element?(back, "#chat-messages .ui-chat-answer", "Pronto.")
    assert Chat.answer_in_progress(id) == nil

    # The screen that was not looking got the notice, with a link to the conversation
    # and nothing of its content; the chat screen did not.
    assert has_element?(other, "#ai-toast", "Resposta pronta")
    assert has_element?(other, ~s|#ai-toast-open[href="/chat/#{id}"]|)
    refute has_element?(other, "#ai-toast", "oi")
    refute has_element?(back, "#ai-toast")

    other |> element("#ai-toast-close") |> render_click()
    refute has_element?(other, "#ai-toast")
  end

  test "a question left without an answer can be asked again", %{conn: conn, user: user} do
    {:ok, conversation} = Chat.start_conversation(user.id, "oi")
    {:ok, _} = Chat.add_user_message(conversation, "oi")
    LLMStub.script(["Agora sim."])

    {:ok, view, _html} = live(conn, ~p"/chat/#{conversation.id}")
    assert has_element?(view, "#chat-error", "A pergunta ficou sem resposta.")

    view |> element("#chat-retry") |> render_click()
    await_reply(view)
    reveal(view)

    refute has_element?(view, "#chat-error")
    assert has_element?(view, "#chat-messages .ui-chat-answer", "Agora sim.")
  end

  test "a failed answer also notifies the other screens", %{conn: conn, user: user} do
    LLMStub.script([{:error, "boom"}, {:error, "boom"}])
    {:ok, conversation} = Chat.start_conversation(user.id, "oi")
    {:ok, _} = Chat.add_user_message(conversation, "oi")
    {:ok, other, _html} = live(conn, ~p"/dashboard")

    {:ok, _pid} = Chat.ask(conversation)
    assert_receive {:chat_reply, _id, {:error, _}}, 5_000

    assert has_element?(other, "#ai-toast", "O chat não conseguiu responder")
  end

  test "blank messages are ignored", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/chat")
    view |> form("#chat-composer", %{"message" => "   "}) |> render_submit()

    assert Chat.list_conversations(user.id) == []
  end
end
