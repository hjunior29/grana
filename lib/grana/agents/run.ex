defmodule Grana.Agents.Run do
  @moduledoc """
  A specialist working for a user in the background, supervised outside the screen that
  asked: leaving the screen does not cancel it, and the outcome waits here (`current/2`)
  until the user dismisses it or asks again. Each run has a name per user (`:search`, or
  `{:analysis, year, month}`), with one run at a time per name. The outcome is also
  broadcast on the user's topic (`subscribe/1`) as
  `{:agent_run, name, {:done, result} | {:error, reason}}`.
  """

  use GenServer, restart: :temporary

  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Grana.PubSub, topic(user_id))

  defp topic(user_id), do: "agent_runs:#{user_id}"

  @doc """
  Runs `fun` (returning `{:ok, result}` or `{:error, reason}`) in the background;
  `input` is kept for the screen to show what was asked. `{:error, :busy}` while a run
  with the same name is still going.
  """
  def start(user_id, name, input, fun) do
    case current(user_id, name) do
      %{outcome: nil} ->
        {:error, :busy}

      _finished_or_none ->
        clear(user_id, name)

        case DynamicSupervisor.start_child(
               Grana.Agents.RunSupervisor,
               {__MODULE__, {user_id, name, input, fun}}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, _pid}} -> {:error, :busy}
        end
    end
  end

  def start_link({user_id, name, input, fun}) do
    GenServer.start_link(__MODULE__, {user_id, name, input, fun}, name: via(user_id, name))
  end

  @doc """
  The user's run with that name: `%{input:, outcome:}` with the outcome nil while it
  runs, `{:ok, result}` or `{:error, reason}` after; nil when there is none.
  """
  def current(user_id, name) do
    GenServer.call(via(user_id, name), :current)
  catch
    :exit, _ -> nil
  end

  def clear(user_id, name) do
    case Registry.lookup(Grana.Agents.RunRegistry, {user_id, name}) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Grana.Agents.RunSupervisor, pid)
      [] -> :ok
    end
  end

  defp via(user_id, name), do: {:via, Registry, {Grana.Agents.RunRegistry, {user_id, name}}}

  @impl true
  def init({user_id, name, input, fun}) do
    state = %{user_id: user_id, name: name, input: input, fun: fun, outcome: nil}
    {:ok, state, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, %{fun: fun} = state) do
    task = Task.Supervisor.async_nolink(Grana.Agents.TaskSupervisor, fun)
    {:noreply, Map.put(state, :task, task)}
  end

  @impl true
  def handle_call(:current, _from, state) do
    {:reply, Map.take(state, [:input, :outcome]), state}
  end

  @impl true
  def handle_info({ref, outcome}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish(state, outcome)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %Task{ref: ref}} = state) do
    {:noreply, finish(state, {:error, :crashed})}
  end

  defp finish(state, outcome) do
    event =
      case outcome do
        {:ok, result} -> {:done, result}
        {:error, reason} -> {:error, reason}
      end

    Phoenix.PubSub.broadcast(Grana.PubSub, topic(state.user_id), {:agent_run, state.name, event})
    %{state | outcome: outcome}
  end
end
