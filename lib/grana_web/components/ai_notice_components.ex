defmodule GranaWeb.AiNoticeComponents do
  @moduledoc "Floating notice of an AI job (chat answer or search build) finished on another screen."
  use GranaWeb, :html

  attr :notice, :map, default: nil, doc: "`@ai_notice` from `GranaWeb.AiNoticesHook`"

  def ai_toast(assigns) do
    ~H"""
    <div :if={@notice} id="ai-toast" role="status" aria-live="polite">
      <div class={[
        "ui-notice ui-toast shadow-lg",
        if(@notice.status == :done, do: "ui-notice-success", else: "ui-notice-error")
      ]}>
        <.icon name={toast_icon(@notice)} class="size-5 shrink-0 self-start" />
        <div class="min-w-0 flex-1">
          <p class="font-semibold">{title(@notice)}</p>
          <.link
            id="ai-toast-open"
            navigate={path(@notice)}
            class="mt-1 inline-block text-sm font-medium underline-offset-2 hover:underline"
          >
            {action(@notice)}
          </.link>
        </div>
        <button
          id="ai-toast-close"
          type="button"
          class="group self-start cursor-pointer"
          aria-label="Fechar"
          phx-click="dismiss_ai_notice"
        >
          <.icon name="hero-x-mark" class="ui-text-tertiary size-5 group-hover:text-base-content" />
        </button>
      </div>
    </div>
    """
  end

  defp toast_icon(%{kind: :chat}), do: "hero-chat-bubble-left-right"
  defp toast_icon(%{kind: :search}), do: "hero-sparkles"
  defp toast_icon(%{kind: :analysis}), do: "hero-sparkles"

  defp title(%{kind: :chat, status: :done}), do: "Resposta pronta"
  defp title(%{kind: :chat}), do: "O chat não conseguiu responder"
  defp title(%{kind: :search, status: :done}), do: "Busca pronta"
  defp title(%{kind: :search}), do: "A IA não conseguiu montar a busca"
  defp title(%{kind: :analysis, status: :done}), do: "Análise pronta"
  defp title(%{kind: :analysis}), do: "A IA não conseguiu analisar o período"

  defp path(%{kind: :chat, conversation_id: id}), do: ~p"/chat/#{id}"
  defp path(%{kind: :search}), do: ~p"/transactions?mode=advanced"

  defp path(%{kind: :analysis, year: year, month: month}),
    do: ~p"/dashboard?#{[year: year, month: if(month == 0, do: "all", else: month)]}"

  defp action(%{kind: :chat}), do: "Ver conversa"
  defp action(%{kind: :search}), do: "Ver busca"
  defp action(%{kind: :analysis}), do: "Ver análise"
end
