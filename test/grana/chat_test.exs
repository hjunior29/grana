defmodule Grana.ChatTest do
  use Grana.DataCase, async: false
  use Mimic

  setup :set_mimic_global

  import Grana.AccountsFixtures

  alias Grana.Chat
  alias Grana.LLMStub

  setup do
    %{user: user_fixture() |> ai_fixture()}
  end

  test "a conversation is titled after its first message", %{user: user} do
    {:ok, short} = Chat.start_conversation(user.id, "  quanto   gastei?  ")
    assert short.title == "quanto gastei?"

    {:ok, long} = Chat.start_conversation(user.id, String.duplicate("a", 80))
    assert String.length(long.title) == 60
    assert String.ends_with?(long.title, "…")
  end

  test "reply saves the answer with its tools and model", %{user: user} do
    {:ok, conversation} = Chat.start_conversation(user.id, "o que tem?")
    {:ok, _} = Chat.add_user_message(conversation, "o que tem?")
    LLMStub.script([{:tool, "get_data_overview", %{}}, "Ainda não há dados."])

    assert {:ok, answer} = Chat.reply(conversation)

    assert answer.role == "assistant"
    assert answer.content == "Ainda não há dados."
    assert answer.ai_model == "gemini-test-model"
    assert [%{"name" => "get_data_overview"}] = answer.tool_calls

    assert [%{role: "user"}, %{role: "assistant"}] =
             Chat.get_conversation(user.id, conversation.id).messages
  end

  test "reply sends the whole conversation and a picked model", %{user: user} do
    {:ok, conversation} = Chat.start_conversation(user.id, "oi")
    {:ok, _} = Chat.add_user_message(conversation, "oi")
    agent = LLMStub.script(["Olá!", "Tudo certo."])
    {:ok, _} = Chat.reply(conversation)
    {:ok, _} = Chat.add_user_message(conversation, "tudo bem?")
    [ref, _model] = user |> Grana.AI.general_choice() |> String.split("|")

    {:ok, answer} = Chat.reply(conversation, Grana.AI.choice(ref, "gemini-pro"))

    assert answer.ai_model == "gemini-pro"
    [_first, {_model, messages}] = LLMStub.calls(agent)
    assert Enum.map(tl(messages), &LLMStub.text/1) == ["oi", "Olá!", "tudo bem?"]
  end

  test "an error saves nothing", %{user: user} do
    {:ok, conversation} = Chat.start_conversation(user.id, "oi")
    {:ok, _} = Chat.add_user_message(conversation, "oi")
    # Streamed first, then once more without streaming.
    LLMStub.script([{:error, "boom"}, {:error, "boom"}])

    assert {:error, "A IA respondeu com erro: boom"} = Chat.reply(conversation)
    assert [%{role: "user"}] = Chat.get_conversation(user.id, conversation.id).messages
  end

  test "ask/2 answers in the background and broadcasts each step", %{user: user} do
    {:ok, conversation} = Chat.start_conversation(user.id, "o que tem?")
    {:ok, _} = Chat.add_user_message(conversation, "o que tem?")
    Chat.subscribe(user.id)
    LLMStub.script([{:tool, "get_data_overview", %{}}, "Nada ainda."])

    assert {:ok, pid} = Chat.ask(conversation)
    assert {:error, :busy} = Chat.ask(conversation)
    id = conversation.id

    assert_receive {:chat_reply, ^id, {:tool, "get_data_overview"}}, 5_000
    assert_receive {:chat_reply, ^id, {:delta, _}}, 5_000
    assert_receive {:chat_reply, ^id, {:done, %{content: "Nada ainda."}}}, 5_000

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, reason} when reason in [:normal, :noproc]
    assert Chat.answer_in_progress(id) == nil

    assert [_, %{role: "assistant", content: "Nada ainda."}] =
             Chat.get_conversation(user.id, id).messages
  end

  test "deleting a conversation stops its answer", %{user: user} do
    test_pid = self()
    {:ok, conversation} = Chat.start_conversation(user.id, "oi")
    {:ok, _} = Chat.add_user_message(conversation, "oi")

    LLMStub.script([
      fn _messages ->
        send(test_pid, :waiting)
        Process.sleep(:infinity)
      end
    ])

    {:ok, pid} = Chat.ask(conversation)
    assert_receive :waiting, 5_000
    assert %{tools: [], draft: ""} = Chat.answer_in_progress(conversation.id)

    ref = Process.monitor(pid)
    {:ok, _} = Chat.delete_conversation(conversation)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    assert Chat.answer_in_progress(conversation.id) == nil
  end

  test "conversations belong to their user, newest first", %{user: user} do
    {:ok, older} = Chat.start_conversation(user.id, "primeira")
    {:ok, newer} = Chat.start_conversation(user.id, "segunda")

    Repo.update_all(Ecto.Query.where(Chat.Conversation, id: ^older.id),
      set: [updated_at: ~U[2026-01-01 00:00:00Z]]
    )

    assert [%{id: id1}, %{id: id2}] = Chat.list_conversations(user.id)
    assert {id1, id2} == {newer.id, older.id}

    other = user_fixture()
    assert Chat.list_conversations(other.id) == []
    assert Chat.get_conversation(other.id, newer.id) == nil

    {:ok, _} = Chat.delete_conversation(newer)
    assert [%{id: ^id2}] = Chat.list_conversations(user.id)
  end
end
