defmodule Grana.Agents.SearchRun do
  @moduledoc """
  The advanced search being built for a user by `Grana.Agents.SearchBuilder`, supervised
  outside the screen that asked: leaving the transactions page does not cancel it, and the
  outcome waits here (`current/1`) until the user dismisses it or asks for another search.
  The outcome is also broadcast on the user's topic (`subscribe/1`) as
  `{:search_build, {:done, result} | {:error, reason}}`.
  """

  use GenServer, restart: :temporary

  alias Grana.Agents.SearchBuilder

  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Grana.PubSub, topic(user_id))

  defp topic(user_id), do: "search_build:#{user_id}"

  @doc "Builds the query in the background; `{:error, :busy}` while one is still being built."
  def start(user_id, request, choice) do
    case current(user_id) do
      %{outcome: nil} ->
        {:error, :busy}

      _finished_or_none ->
        clear(user_id)

        case DynamicSupervisor.start_child(
               Grana.Agents.SearchSupervisor,
               {__MODULE__, {user_id, request, choice}}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, _pid}} -> {:error, :busy}
        end
    end
  end

  def start_link({user_id, request, choice}) do
    GenServer.start_link(__MODULE__, {user_id, request, choice}, name: via(user_id))
  end

  @doc """
  The user's search build: `%{request:, outcome:}` with the outcome nil while it runs,
  `{:ok, result}` or `{:error, reason}` after; nil when there is none.
  """
  def current(user_id) do
    GenServer.call(via(user_id), :current)
  catch
    :exit, _ -> nil
  end

  def clear(user_id) do
    case Registry.lookup(Grana.Agents.SearchRegistry, user_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Grana.Agents.SearchSupervisor, pid)
      [] -> :ok
    end
  end

  defp via(user_id), do: {:via, Registry, {Grana.Agents.SearchRegistry, user_id}}

  @impl true
  def init({user_id, request, choice}) do
    state = %{user_id: user_id, request: request, choice: choice, outcome: nil}
    {:ok, state, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, %{user_id: user_id, request: request, choice: choice} = state) do
    task =
      Task.Supervisor.async_nolink(Grana.Agents.TaskSupervisor, fn ->
        SearchBuilder.run(user_id, request, choice)
      end)

    {:noreply, Map.put(state, :task, task)}
  end

  @impl true
  def handle_call(:current, _from, state) do
    {:reply, Map.take(state, [:request, :outcome]), state}
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

    Phoenix.PubSub.broadcast(Grana.PubSub, topic(state.user_id), {:search_build, event})
    %{state | outcome: outcome}
  end
end
