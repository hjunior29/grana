defmodule Grana.Chat.Reply do
  @moduledoc """
  One answer being written, supervised outside the screen that asked for it: leaving the
  chat (or closing the tab) does not cancel it. The coordinator runs in a task; its
  events are kept here, so a screen that opens the conversation mid-answer can catch up
  (`snapshot/1`), and broadcast on the user's chat topic (`Grana.Chat.subscribe/1`) as
  `{:chat_reply, conversation_id, event}` with `{:tool, name}`, `{:delta, text}`,
  `{:done, message}` or `{:error, reason}`.
  """

  use GenServer, restart: :temporary

  alias Grana.Chat

  def start(conversation, choice) do
    case DynamicSupervisor.start_child(Chat.ReplySupervisor, {__MODULE__, {conversation, choice}}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :busy}
    end
  end

  def start_link({conversation, choice}) do
    GenServer.start_link(__MODULE__, {conversation, choice}, name: via(conversation.id))
  end

  @doc "Tools called and text written so far, or nil when nothing is being answered."
  def snapshot(conversation_id) do
    GenServer.call(via(conversation_id), :snapshot)
  catch
    :exit, _ -> nil
  end

  def stop(conversation_id) do
    case Registry.lookup(Chat.ReplyRegistry, conversation_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Chat.ReplySupervisor, pid)
      [] -> :ok
    end
  end

  defp via(conversation_id), do: {:via, Registry, {Chat.ReplyRegistry, conversation_id}}

  @impl true
  def init({conversation, choice}) do
    {:ok, %{conversation: conversation, choice: choice, tools: [], draft: ""}, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, %{conversation: conversation, choice: choice} = state) do
    reply = self()

    task =
      Task.Supervisor.async_nolink(Chat.TaskSupervisor, fn ->
        Chat.reply(conversation, choice, &GenServer.cast(reply, {:event, &1}))
      end)

    {:noreply, Map.put(state, :task, task)}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, Map.take(state, [:tools, :draft]), state}
  end

  @impl true
  def handle_cast({:event, {:tool, name} = event}, state) do
    # Text written before a tool call belongs to an intermediate step, not the answer.
    {:noreply, state |> Map.merge(%{tools: state.tools ++ [name], draft: ""}) |> broadcast(event)}
  end

  def handle_cast({:event, {:delta, text} = event}, state) do
    {:noreply, state |> Map.put(:draft, state.draft <> text) |> broadcast(event)}
  end

  @impl true
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, message} -> broadcast(state, {:done, message})
      {:error, reason} -> broadcast(state, {:error, reason})
    end

    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %Task{ref: ref}} = state) do
    broadcast(state, {:error, :crashed})
    {:stop, :normal, state}
  end

  defp broadcast(%{conversation: conversation} = state, event) do
    Chat.broadcast(conversation.user_id, {:chat_reply, conversation.id, event})
    state
  end
end
