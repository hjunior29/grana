defmodule Grana.Chat do
  @moduledoc """
  Conversations with the chat coordinator (`Grana.Agents.Coordinator`), saved per user.
  """

  import Ecto.Query

  alias Grana.Agents.Coordinator
  alias Grana.Chat.Conversation
  alias Grana.Chat.Message
  alias Grana.Chat.Reply
  alias Grana.Repo

  @doc "Events of the user's answers in progress: `{:chat_reply, conversation_id, event}`."
  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Grana.PubSub, topic(user_id))

  def broadcast(user_id, event), do: Phoenix.PubSub.broadcast(Grana.PubSub, topic(user_id), event)

  defp topic(user_id), do: "chat:#{user_id}"

  @title_length 60

  def list_conversations(user_id) do
    Repo.all(
      from(c in Conversation,
        where: c.user_id == ^user_id,
        order_by: [desc: c.updated_at, desc: c.id]
      )
    )
  end

  def get_conversation(user_id, id) do
    Conversation
    |> where([c], c.user_id == ^user_id and c.id == ^id)
    |> preload(:messages)
    |> Repo.one()
  end

  @doc "Starts a conversation titled after its first message."
  def start_conversation(user_id, text) do
    %Conversation{user_id: user_id}
    |> Conversation.changeset(%{title: title(text)})
    |> Repo.insert()
  end

  def delete_conversation(%Conversation{} = conversation) do
    Reply.stop(conversation.id)
    Repo.delete(conversation)
  end

  @doc """
  Answers the conversation's last message in the background (`Grana.Chat.Reply`): the
  answer is saved and broadcast even if the screen that asked is gone. `{:error, :busy}`
  while an answer for the conversation is still being written.
  """
  def ask(%Conversation{} = conversation, choice \\ nil), do: Reply.start(conversation, choice)

  @doc "Tools and text of an answer in progress for the conversation, or nil."
  def answer_in_progress(conversation_id), do: Reply.snapshot(conversation_id)

  def add_user_message(%Conversation{} = conversation, text),
    do: add_message(conversation, %{role: "user", content: String.trim(text)})

  @doc """
  Asks the coordinator to answer the conversation's last message and saves the answer.
  `choice` picks the coordinator model; `notify` gets the coordinator's events
  (`{:tool, name}`, `{:delta, text}`) while it works.
  """
  def reply(%Conversation{} = conversation, choice \\ nil, notify \\ fn _event -> :ok end) do
    history =
      Repo.all(from(m in Message, where: m.conversation_id == ^conversation.id, order_by: m.id))

    with {:ok, answer} <- Coordinator.run(conversation.user_id, history, choice, notify) do
      add_message(conversation, %{
        role: "assistant",
        content: answer.content,
        tool_calls: answer.tool_calls,
        ai_provider: answer.ai_provider,
        ai_model: answer.ai_model
      })
    end
  end

  defp add_message(conversation, attrs) do
    Repo.transaction(fn ->
      message =
        %Message{conversation_id: conversation.id}
        |> Message.changeset(attrs)
        |> Repo.insert!()

      conversation
      |> Ecto.Changeset.change(updated_at: DateTime.utc_now(:second))
      |> Repo.update!()

      message
    end)
  end

  defp title(text) do
    text = text |> String.trim() |> String.replace(~r/\s+/, " ")

    if String.length(text) > @title_length,
      do: String.slice(text, 0, @title_length - 1) <> "…",
      else: text
  end
end
