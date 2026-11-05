defmodule GranaWeb.AiNoticesHook do
  @moduledoc """
  Tells every logged-in screen when an AI job finishes somewhere else: a chat answer
  (`Grana.Chat.Reply`), an advanced search build or a period analysis (`Grana.Agents.Run`).
  Keeps `@ai_notice` (shown by `Layouts.app` as a floating notice with a link to the
  result) and handles `dismiss_ai_notice`. The chat, transactions and dashboard screens
  handle their own events, so no notice there.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Grana.Agents.Run
  alias Grana.Chat

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      user_id = socket.assigns.current_scope.user.id
      Chat.subscribe(user_id)
      Run.subscribe(user_id)
    end

    {:cont,
     socket
     |> assign(:ai_notice, nil)
     |> attach_hook(:ai_notices, :handle_info, &handle_info/2)
     |> attach_hook(:ai_notices_dismiss, :handle_event, &handle_event/3)}
  end

  defp handle_info({:chat_reply, _id, _event}, %{view: GranaWeb.ChatLive} = socket),
    do: {:cont, socket}

  defp handle_info({:chat_reply, id, {status, _}}, socket) when status in [:done, :error],
    do: {:halt, assign(socket, :ai_notice, %{kind: :chat, status: status, conversation_id: id})}

  defp handle_info({:chat_reply, _id, _event}, socket), do: {:halt, socket}

  defp handle_info({:agent_run, :search, _event}, %{view: GranaWeb.TransactionsLive} = socket),
    do: {:cont, socket}

  defp handle_info({:agent_run, :search, {status, _}}, socket),
    do: {:halt, assign(socket, :ai_notice, %{kind: :search, status: status})}

  defp handle_info({:agent_run, {:analysis, _, _}, _}, %{view: GranaWeb.DashboardLive} = socket),
    do: {:cont, socket}

  defp handle_info({:agent_run, {:analysis, year, month}, {status, _}}, socket) do
    notice = %{kind: :analysis, status: status, year: year, month: month}
    {:halt, assign(socket, :ai_notice, notice)}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("dismiss_ai_notice", _params, socket),
    do: {:halt, assign(socket, :ai_notice, nil)}

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
