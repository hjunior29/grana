defmodule GranaWeb.ChatRepliesHook do
  @moduledoc """
  Tells every logged-in screen when a chat answer finishes somewhere else: keeps
  `@chat_notice` (shown by `Layouts.app` as a floating notice with a link to the
  conversation) and handles `dismiss_chat_notice`. The chat screen showing that very
  conversation handles the event itself, so no notice there.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Grana.Chat

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Chat.subscribe(socket.assigns.current_scope.user.id)

    {:cont,
     socket
     |> assign(:chat_notice, nil)
     |> attach_hook(:chat_replies, :handle_info, &handle_info/2)
     |> attach_hook(:chat_replies_dismiss, :handle_event, &handle_event/3)}
  end

  # The chat screen handles its own events; every other screen only keeps the notice.
  defp handle_info({:chat_reply, _id, _event}, %{view: GranaWeb.ChatLive} = socket),
    do: {:cont, socket}

  defp handle_info({:chat_reply, conversation_id, {kind, _} = event}, socket)
       when kind in [:done, :error],
       do: {:halt, assign(socket, :chat_notice, notice(socket, conversation_id, event))}

  defp handle_info({:chat_reply, _id, _event}, socket), do: {:halt, socket}
  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("dismiss_chat_notice", _params, socket),
    do: {:halt, assign(socket, :chat_notice, nil)}

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp notice(socket, conversation_id, {kind, _}) do
    user_id = socket.assigns.current_scope.user.id

    case Chat.get_conversation(user_id, conversation_id) do
      nil -> nil
      conversation -> %{conversation_id: conversation_id, title: conversation.title, kind: kind}
    end
  end
end
