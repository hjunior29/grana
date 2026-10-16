defmodule GranaWeb.ChatComponents do
  @moduledoc "Floating notice of a chat answer finished on another screen."
  use GranaWeb, :html

  attr :notice, :map, default: nil, doc: "`@chat_notice` from `GranaWeb.ChatRepliesHook`"

  def reply_toast(assigns) do
    ~H"""
    <div :if={@notice} id="chat-reply-toast" role="status" aria-live="polite">
      <div class={[
        "ui-notice ui-toast shadow-lg",
        if(@notice.kind == :done, do: "ui-notice-success", else: "ui-notice-error")
      ]}>
        <.icon name="hero-chat-bubble-left-right" class="size-5 shrink-0 self-start" />
        <div class="min-w-0 flex-1">
          <p class="font-semibold">
            {if @notice.kind == :done, do: "Resposta pronta", else: "O chat não conseguiu responder"}
          </p>
          <p class="ui-private-name ui-help truncate">{@notice.title}</p>
          <.link
            id="chat-reply-toast-open"
            navigate={~p"/chat/#{@notice.conversation_id}"}
            class="mt-1 inline-block text-sm font-medium underline-offset-2 hover:underline"
          >
            Ver conversa
          </.link>
        </div>
        <button
          id="chat-reply-toast-close"
          type="button"
          class="group self-start cursor-pointer"
          aria-label="Fechar"
          phx-click="dismiss_chat_notice"
        >
          <.icon name="hero-x-mark" class="ui-text-tertiary size-5 group-hover:text-base-content" />
        </button>
      </div>
    </div>
    """
  end
end
