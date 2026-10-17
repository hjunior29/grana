defmodule GranaWeb.ChatLive do
  use GranaWeb, :live_view

  alias Grana.AI
  alias Grana.Banking.PrivateNames
  alias Grana.Chat
  alias GranaWeb.AiComponents
  alias GranaWeb.ChatHTML

  on_mount GranaWeb.ModelChoicesHook
  on_mount {GranaWeb.DataHook, :reload_on_data}

  @suggestions [
    "Quanto gastei este mês?",
    "Quais foram meus maiores gastos no último ano?",
    "Analise o meu último mês",
    "Monte uma busca de gastos com delivery"
  ]

  # Safety net for the hand-off from the animated draft to the saved message, when the
  # browser does not report that the animation finished (e.g. a tab in the background).
  @flush_after 6_000

  # Each step the coordinator took: what it reads (data), who it delegated to (agent)
  # or a plain tool, each with its own icon.
  @tools %{
    "get_data_overview" => {"Visão geral dos dados", :data},
    "get_period_summary" => {"Resumo do período", :data},
    "get_monthly_totals" => {"Totais por mês", :data},
    "search_transactions" => {"Busca de transações", :data},
    "get_fixed_expenses" => {"Despesas fixas", :data},
    "get_installments" => {"Parcelas", :data},
    "get_goals" => {"Metas", :data},
    "list_merchants" => {"Estabelecimentos", :data},
    "analyze_period" => {"Especialista de análise", :agent},
    "build_search" => {"Especialista de pesquisa", :agent}
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:private_names, PrivateNames.pattern(socket.assigns.current_scope.user.id))
     |> assign(:conversation, nil)
     |> assign(:pending, nil)
     |> assign(:pending_conversation_id, nil)
     |> assign(:draft, "")
     |> assign(:finished, nil)
     |> assign(:error, nil)
     |> assign(:model_choice, "")
     |> assign(:delete_target, nil)
     |> assign(:show_api_key_alert, false)
     |> assign(:suggestions, @suggestions)
     |> stream(:messages, [])
     |> load_conversations()}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket),
    do: {:noreply, open(socket, nil)}

  def handle_params(%{"id" => id}, _uri, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Integer.parse(id) do
      {id, ""} when id == socket.assigns.conversation_id ->
        {:noreply, socket}

      {id, ""} ->
        case Chat.get_conversation(user_id, id) do
          nil ->
            {:noreply,
             socket |> put_flash(:error, "Conversa não encontrada.") |> push_patch(to: ~p"/chat")}

          conversation ->
            {:noreply, open(socket, conversation)}
        end

      _ ->
        {:noreply, push_patch(socket, to: ~p"/chat")}
    end
  end

  # /chat lands on the latest conversation, so a visit does not start a new one each time.
  def handle_params(_params, _uri, socket) do
    case Chat.list_conversations(socket.assigns.current_scope.user.id) do
      [latest | _] -> {:noreply, push_patch(socket, to: ~p"/chat/#{latest.id}")}
      [] -> {:noreply, open(socket, nil)}
    end
  end

  defp open(socket, conversation) do
    socket
    |> assign(:conversation, conversation)
    |> assign(:conversation_id, conversation && conversation.id)
    |> assign(:error, nil)
    |> stream(:messages, if(conversation, do: conversation.messages, else: []), reset: true)
    |> resume_answer()
    |> load_conversations()
  end

  # An answer started earlier (here or in another tab) is still being written.
  defp resume_answer(%{assigns: %{conversation: nil}} = socket), do: assign_idle(socket)

  defp resume_answer(%{assigns: %{conversation: conversation}} = socket) do
    case Chat.answer_in_progress(conversation.id) do
      nil ->
        # A question left without an answer (the server restarted mid-answer, for
        # instance) gets the retry button.
        socket
        |> assign_idle()
        |> assign(:error, if(unanswered?(conversation), do: "A pergunta ficou sem resposta."))

      %{tools: tools, draft: draft} ->
        assign(socket,
          pending: tools,
          pending_conversation_id: conversation.id,
          draft: draft,
          finished: nil
        )
    end
  end

  defp assign_idle(socket),
    do: assign(socket, pending: nil, pending_conversation_id: nil, draft: "", finished: nil)

  defp unanswered?(%{messages: messages}), do: match?(%{role: "user"}, List.last(messages))

  defp load_conversations(socket) do
    conversations = Chat.list_conversations(socket.assigns.current_scope.user.id)

    socket
    |> assign(:conversation_id, socket.assigns[:conversation_id])
    |> assign(:has_conversations, conversations != [])
    |> stream(:conversations, conversations, reset: true)
  end

  @impl true
  def handle_event("composer_change", params, socket) do
    {:noreply, assign(socket, :model_choice, params["model"] || socket.assigns.model_choice)}
  end

  def handle_event("send", %{"message" => text} = params, socket) do
    text = String.trim(text)
    choice = blank_to_nil(params["model"] || socket.assigns.model_choice)
    user = socket.assigns.current_scope.user

    cond do
      text == "" or busy?(socket) ->
        {:noreply, socket}

      AI.resolve(user, "chat", choice) == {:error, :no_api_key} ->
        {:noreply, assign(socket, :show_api_key_alert, true)}

      true ->
        {:noreply, send_message(socket, text, choice)}
    end
  end

  def handle_event("answer_revealed", _params, socket), do: {:noreply, flush_answer(socket)}

  def handle_event("retry", _params, socket) do
    {:noreply, ask(socket, blank_to_nil(socket.assigns.model_choice))}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_target, String.to_integer(id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_target, nil)}
  end

  def handle_event("delete_conversation", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Chat.get_conversation(user_id, socket.assigns.delete_target) do
      nil ->
        {:noreply, assign(socket, :delete_target, nil)}

      conversation ->
        {:ok, _} = Chat.delete_conversation(conversation)
        socket = assign(socket, :delete_target, nil)

        if conversation.id == socket.assigns.conversation_id,
          do: {:noreply, push_patch(socket, to: ~p"/chat")},
          else: {:noreply, load_conversations(socket)}
    end
  end

  def handle_event("dismiss_api_alert", _params, socket) do
    {:noreply, assign(socket, :show_api_key_alert, false)}
  end

  defp send_message(socket, text, choice) do
    user_id = socket.assigns.current_scope.user.id

    {socket, conversation} =
      case socket.assigns.conversation do
        nil ->
          {:ok, conversation} = Chat.start_conversation(user_id, text)

          {socket
           |> assign(:conversation, conversation)
           |> assign(:conversation_id, conversation.id)
           |> push_patch(to: ~p"/chat/#{conversation.id}"), conversation}

        conversation ->
          {socket, conversation}
      end

    {:ok, message} = Chat.add_user_message(conversation, text)

    socket
    |> stream_insert(:messages, message)
    |> load_conversations()
    |> ask(choice)
  end

  defp busy?(socket),
    do:
      socket.assigns.pending != nil and
        socket.assigns.pending_conversation_id == socket.assigns.conversation_id

  defp ask(socket, choice) do
    conversation = socket.assigns.conversation

    case Chat.ask(conversation, choice) do
      {:ok, _pid} ->
        assign(socket,
          pending: [],
          pending_conversation_id: conversation.id,
          draft: "",
          finished: nil,
          error: nil
        )

      {:error, :busy} ->
        resume_answer(socket)
    end
  end

  @impl true
  def handle_info({:chat_reply, id, event}, %{assigns: %{conversation_id: id}} = socket) do
    {:noreply, apply_event(socket, event)}
  end

  # Another conversation: the list order changes and the floating notice shows up.
  def handle_info({:chat_reply, id, {status, _}}, socket) when status in [:done, :error] do
    {:noreply,
     socket
     |> assign(:ai_notice, %{kind: :chat, status: status, conversation_id: id})
     |> load_conversations()}
  end

  def handle_info({:chat_reply, _id, _event}, socket), do: {:noreply, socket}

  def handle_info({:flush_answer, id}, %{assigns: %{finished: %{id: id}}} = socket),
    do: {:noreply, flush_answer(socket)}

  def handle_info({:flush_answer, _id}, socket), do: {:noreply, socket}

  # Text written before a tool call belongs to an intermediate step, not the answer.
  defp apply_event(socket, {:tool, name}),
    do: socket |> update(:pending, &((&1 || []) ++ [name])) |> assign(:draft, "")

  defp apply_event(socket, {:delta, text}), do: update(socket, :draft, &(&1 <> text))

  # The draft gets the whole answer and keeps animating; the saved message takes its
  # place once the screen has caught up (`answer_revealed`).
  defp apply_event(socket, {:done, message}) do
    Process.send_after(self(), {:flush_answer, message.id}, @flush_after)

    assign(socket,
      pending: socket.assigns.pending || [],
      draft: message.content,
      finished: message
    )
  end

  defp apply_event(socket, {:error, reason}),
    do: assign(socket, pending: nil, draft: "", error: error_message(reason))

  defp flush_answer(%{assigns: %{finished: nil}} = socket), do: socket

  defp flush_answer(%{assigns: %{finished: message}} = socket) do
    socket =
      if message.conversation_id == socket.assigns.conversation_id,
        do: stream_insert(socket, :messages, message),
        else: socket

    socket
    |> assign(pending: nil, draft: "", finished: nil)
    |> load_conversations()
  end

  defp error_message(:no_api_key), do: "Cadastre um provedor de IA nas Configurações."
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(_reason), do: "Não foi possível responder agora. Tente de novo."

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      import_queue={@import_queue}
      ai_notice={@ai_notice}
      import_toast={:top}
    >
      <div class="max-w-6xl mx-auto">
        <.page_header
          title="Chat"
          subtitle="Converse com os seus dados: meses, anos, bancos, contas e categorias"
        >
          <:actions>
            <.button
              :if={@has_data}
              id="new-conversation"
              patch={~p"/chat/new"}
              variant="secondary"
              size="sm"
              icon="hero-plus"
            >
              Nova conversa
            </.button>
          </:actions>
        </.page_header>

        <.no_data
          :if={!@has_data}
          id="chat-no-data"
          icon="hero-chat-bubble-left-right"
          text="O chat responde com os seus números: quanto gastou, onde, em que mês. Ele precisa de transações para conversar."
        />

        <div :if={@has_data} class="grid grid-cols-1 gap-4 lg:grid-cols-[16rem_minmax(0,1fr)]">
          <aside class="min-w-0">
            <button
              type="button"
              class="ui-label flex cursor-pointer items-center gap-1 lg:hidden"
              phx-click={
                JS.toggle_class("hidden", to: "#conversations-panel")
                |> JS.toggle_class("rotate-90", to: "#conversations-chevron")
              }
            >
              <span id="conversations-chevron" class="inline-flex transition-transform">
                <.icon name="hero-chevron-right" class="size-4" />
              </span>
              Conversas
            </button>
            <div id="conversations-panel" class="mt-2 hidden lg:mt-0 lg:block">
              <p class="ui-section-title mb-2 hidden lg:block">Conversas</p>
              <.conversation_list streams={@streams} active={@conversation_id} />
              <p :if={!@has_conversations} id="conversations-empty" class="ui-help">
                As conversas ficam salvas aqui.
              </p>
            </div>
          </aside>

          <section id="chat-panel" class="ui-chat-panel card bg-base-200">
            <div id="chat-scroll" class="ui-chat-scroll" phx-hook=".ChatScroll">
              <div
                :if={@conversation == nil and @pending == nil}
                id="chat-welcome"
                class="flex flex-col items-center px-4 py-10 text-center"
              >
                <span class="ui-chat-avatar mb-3 size-10">
                  <.icon name="hero-sparkles" class="size-5" />
                </span>
                <h2 class="ui-card-title">Pergunte sobre o seu dinheiro</h2>
                <p class="ui-help mt-1 max-w-md">
                  As respostas vêm dos seus dados, consultados na hora. Peça também uma análise do mês ou uma busca pronta para a tela de transações.
                </p>
                <div class="mt-5 flex max-w-xl flex-wrap justify-center gap-2">
                  <button
                    :for={suggestion <- @suggestions}
                    type="button"
                    class="ui-chip ui-chip-outline"
                    phx-click="send"
                    phx-value-message={suggestion}
                  >
                    {suggestion}
                  </button>
                </div>
              </div>

              <div id="chat-messages" phx-update="stream" class="flex flex-col gap-5">
                <.chat_message
                  :for={{dom_id, message} <- @streams.messages}
                  id={dom_id}
                  message={message}
                  names={@private_names}
                />
              </div>

              <div
                :if={@pending && @pending_conversation_id == @conversation_id}
                id="chat-pending"
                class="ui-chat-row ui-chat-enter"
              >
                <span class="ui-chat-avatar"><.icon name="hero-sparkles" class="size-4" /></span>
                <div class="min-w-0 flex-1">
                  <p :if={@draft == ""} class="ui-help flex items-center gap-2">
                    <span class="loading loading-dots loading-xs"></span>
                    {if @pending == [], do: "Pensando…", else: "Consultando seus dados…"}
                  </p>
                  <div
                    :if={@draft != ""}
                    id="chat-draft"
                    phx-hook=".StreamText"
                    data-done={to_string(@finished != nil)}
                  >
                    <div data-source hidden phx-no-format>{ChatHTML.render_partial(@draft, @private_names)}</div>
                    <div
                      id="chat-draft-text"
                      class="ui-chat-answer ui-chat-html"
                      phx-update="ignore"
                      phx-no-format
                    ><span class="ui-chat-caret"></span></div>
                  </div>
                  <div :if={@pending != []} class="mt-2 flex flex-wrap gap-1.5">
                    <.step :for={name <- Enum.uniq(@pending)} name={name} />
                  </div>
                </div>
              </div>

              <div :if={@error} id="chat-error" class="ui-chat-row ui-chat-enter">
                <span class="ui-chat-avatar"><.icon name="hero-sparkles" class="size-4" /></span>
                <.notice tone={:error} class="min-w-0 flex-1">
                  {@error}
                  <:action>
                    <.button id="chat-retry" type="button" variant="ghost" size="sm" phx-click="retry">
                      Tentar de novo
                    </.button>
                  </:action>
                </.notice>
              </div>
            </div>

            <form
              id="chat-composer"
              class="ui-chat-composer"
              phx-submit="send"
              phx-change="composer_change"
            >
              <textarea
                id="chat-input"
                name="message"
                rows="1"
                class="ui-chat-input"
                placeholder="Pergunte sobre seus gastos, receitas, bancos ou categorias"
                aria-label="Mensagem"
                phx-hook=".ChatComposer"
                disabled={@pending != nil}
              ></textarea>
              <div class="flex items-center justify-between gap-2">
                <AiComponents.model_picker
                  id="chat-model"
                  choices={@model_choices}
                  default={@model_defaults["chat"]}
                  value={@model_choice}
                />
                <button
                  id="chat-send"
                  type="submit"
                  class="btn btn-primary btn-sm btn-square"
                  aria-label="Enviar"
                  disabled={@pending != nil}
                >
                  <.icon name="hero-arrow-up" class="size-4" />
                </button>
              </div>
            </form>
          </section>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".ChatScroll">
          export default {
            mounted() {
              this.toBottom()
              this.observer = new MutationObserver(() => this.toBottom())
              this.observer.observe(this.el, { childList: true, subtree: true })
            },
            toBottom() { this.el.scrollTop = this.el.scrollHeight },
            destroyed() { this.observer && this.observer.disconnect() }
          }
        </script>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".StreamText">
          // Reveals the streamed answer at a steady pace: faster when a big chunk arrives,
          // never in one jump. The hidden [data-source] holds the text sent by the server
          // (with the privacy spans), and a growing prefix of it is copied to the screen.
          const copyPrefix = (source, limit) => {
            const fragment = document.createDocumentFragment()
            let left = limit
            const walk = (node, parent) => {
              for (const child of node.childNodes) {
                if (left <= 0) return
                if (child.nodeType === Node.TEXT_NODE) {
                  const text = child.textContent.slice(0, left)
                  left -= text.length
                  parent.appendChild(document.createTextNode(text))
                } else if (child.nodeType === Node.ELEMENT_NODE) {
                  const copy = child.cloneNode(false)
                  parent.appendChild(copy)
                  walk(child, copy)
                }
              }
            }
            walk(source, fragment)
            return fragment
          }

          export default {
            mounted() {
              this.source = this.el.querySelector("[data-source]")
              this.target = this.el.querySelector("#chat-draft-text")
              this.caret = this.target.querySelector(".ui-chat-caret")
              this.shown = 0
              this.budget = 0
              this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
              this.observer = new MutationObserver(() => this.kick())
              this.observer.observe(this.source, { childList: true, subtree: true, characterData: true })
              this.kick()
            },
            updated() { this.kick() },
            kick() {
              if (!this.frame) this.frame = requestAnimationFrame(() => this.step())
            },
            step() {
              this.frame = null
              const total = this.source.textContent.length
              const backlog = total - this.shown

              if (backlog > 0) {
                this.budget += this.reduced ? backlog : Math.max(0.6, backlog / 28)
                const count = Math.floor(this.budget)
                if (count > 0) {
                  this.budget -= count
                  this.shown = Math.min(total, this.shown + count)
                  this.target.replaceChildren(copyPrefix(this.source, this.shown))
                  this.placeCaret()
                }
                this.kick()
              } else if (this.el.dataset.done === "true" && !this.reported) {
                this.reported = true
                this.pushEvent("answer_revealed", {})
              }
            },
            // The caret follows the last character, even inside a list item or a table cell.
            placeCaret() {
              const walker = document.createTreeWalker(this.target, NodeFilter.SHOW_TEXT)
              let last = null
              while (walker.nextNode()) last = walker.currentNode
              ;(last ? last.parentNode : this.target).appendChild(this.caret)
            },
            destroyed() {
              if (this.frame) cancelAnimationFrame(this.frame)
              this.observer.disconnect()
            }
          }
        </script>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".ChatComposer">
          export default {
            mounted() {
              this.el.addEventListener("keydown", (e) => {
                if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
                  e.preventDefault()
                  if (this.el.value.trim() !== "") this.el.form.requestSubmit()
                }
              })
              this.el.form.addEventListener("submit", () => {
                setTimeout(() => { this.el.value = "" }, 0)
              })
            },
            updated() { if (!this.el.disabled) this.el.focus() }
          }
        </script>

        <.confirm_modal
          :if={@delete_target}
          id="delete-conversation-modal"
          open
          title="Apagar conversa"
          confirm="Apagar"
          loading="Apagando…"
          on_confirm={JS.push("delete_conversation")}
          on_cancel={JS.push("cancel_delete")}
        >
          A conversa e as respostas dela serão apagadas. Seus dados financeiros não mudam.
        </.confirm_modal>

        <.ai_required_modal
          :if={@show_api_key_alert}
          reason="O chat usa IA para entender as perguntas e responder com os seus dados."
        />
      </div>
    </Layouts.app>
    """
  end

  attr :streams, :any, required: true
  attr :active, :any, required: true

  defp conversation_list(assigns) do
    ~H"""
    <ul id="conversations" phx-update="stream" class="ui-chat-conversations">
      <li
        :for={{dom_id, conversation} <- @streams.conversations}
        id={dom_id}
        class={["ui-chat-conversation", conversation.id == @active && "ui-chat-conversation-active"]}
      >
        <.link patch={~p"/chat/#{conversation.id}"} class="min-w-0 flex-1">
          <span class="ui-private-name ui-body block truncate">{conversation.title}</span>
          <span class="ui-caption">{format_date(conversation.updated_at)}</span>
        </.link>
        <button
          type="button"
          class="ui-chat-conversation-delete"
          aria-label={"Apagar a conversa #{conversation.title}"}
          phx-click="confirm_delete"
          phx-value-id={conversation.id}
        >
          <.icon name="hero-trash" class="size-4" />
        </button>
      </li>
    </ul>
    """
  end

  attr :id, :string, required: true
  attr :message, :any, required: true
  attr :names, :any, default: nil

  defp chat_message(%{message: %{role: "user"}} = assigns) do
    ~H"""
    <div id={@id} class="ui-chat-row ui-chat-enter justify-end">
      <p class="ui-chat-bubble"><.private_text text={@message.content} /></p>
    </div>
    """
  end

  defp chat_message(assigns) do
    assigns =
      assigns
      |> assign(:tools, Enum.reject(assigns.message.tool_calls, & &1["error"]))
      |> assign(:queries, for(%{"query" => query} <- assigns.message.tool_calls, do: query))

    ~H"""
    <div id={@id} class="ui-chat-row">
      <span class="ui-chat-avatar"><.icon name="hero-sparkles" class="size-4" /></span>
      <div class="min-w-0 flex-1">
        <div class="ui-chat-answer ui-chat-html">
          {ChatHTML.render(@message.content, @names)}
        </div>
        <div :for={query <- @queries} class="mt-2">
          <.link
            navigate={~p"/transactions?#{[mode: "advanced", q: query]}"}
            class="ui-ai-query"
            title="Abrir na pesquisa avançada"
          >
            <code class="ui-query-code">{query}</code>
            <span class="ui-ai-query-action">
              <.icon name="hero-arrow-top-right-on-square" class="size-3.5" /> Abrir
            </span>
          </.link>
        </div>
        <div class="mt-2 flex flex-wrap items-center gap-1.5">
          <.step :for={name <- @tools |> Enum.map(& &1["name"]) |> Enum.uniq()} name={name} />
          <span
            :if={@message.ai_model}
            class="ui-caption inline-flex items-center gap-1"
            title={"#{@message.ai_provider} · #{@message.ai_model}"}
          >
            <.icon name="hero-cpu-chip" class="size-3.5" /> {@message.ai_model}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true

  defp step(assigns) do
    {label, kind} = Map.get(@tools, assigns.name, {assigns.name, :tool})
    assigns = assign(assigns, label: label, kind: kind)

    ~H"""
    <span class={["ui-chat-step", "ui-chat-step-#{@kind}"]} title={step_title(@kind)}>
      <.icon name={step_icon(@kind)} class="size-3" /> {@label}
    </span>
    """
  end

  defp step_icon(:data), do: "hero-circle-stack"
  defp step_icon(:agent), do: "hero-sparkles"
  defp step_icon(:tool), do: "hero-wrench-screwdriver"

  defp step_title(:data), do: "Dados consultados no banco"
  defp step_title(:agent), do: "Especialista acionado"
  defp step_title(:tool), do: "Ferramenta usada"

  defp format_date(datetime) do
    datetime |> DateTime.add(-3, :hour) |> Calendar.strftime("%d/%m %H:%M")
  end
end
