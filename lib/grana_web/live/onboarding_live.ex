defmodule GranaWeb.OnboardingLive do
  use GranaWeb, :live_view

  alias Grana.Accounts
  alias GranaWeb.AccountComponents
  alias GranaWeb.AiComponents
  alias GranaWeb.OpenFinanceComponents

  on_mount GranaWeb.AiSettingsHooks
  on_mount GranaWeb.SmtpHooks
  on_mount GranaWeb.OpenFinanceHooks

  @steps [
    %{id: :appearance, title: "Aparência", icon: "hero-paint-brush"},
    %{id: :smtp, title: "Email", icon: "hero-envelope"},
    %{id: :ai, title: "Inteligência artificial", icon: "hero-sparkles"},
    %{id: :open_finance, title: "Open Finance", icon: "hero-link"},
    %{id: :done, title: "Pronto", icon: "hero-check-circle"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hide_nav>
      <div id="onboarding" class="mx-auto max-w-xl py-4 sm:py-8">
        <ol id="onboarding-steps" class="mb-6 flex items-center justify-center gap-1.5">
          <li
            :for={step <- @steps}
            id={"onboarding-step-#{step.id}"}
            title={step.title}
            class={[
              "flex size-8 items-center justify-center rounded-full transition-colors",
              if(step_index(step.id) <= step_index(@step),
                do: "bg-primary text-primary-content",
                else: "ui-text-tertiary bg-base-200"
              )
            ]}
          >
            <.icon name={step.icon} class="size-4" />
          </li>
        </ol>

        <%= case @step do %>
          <% :appearance -> %>
            <.step_card title="Aparência" subtitle="Escolha o tema e o estilo visual do Grana.">
              <div class="mb-5 flex items-center justify-between gap-4">
                <p class="ui-body">Tema</p>
                <Layouts.theme_toggle persist />
              </div>
              <div class="flex flex-col gap-3">
                <p class="ui-body">Estilo visual</p>
                <Layouts.visual_style_toggle persist grid />
              </div>
              <p class="ui-help mt-4">Você pode mudar isso depois em Configurações.</p>
            </.step_card>
          <% :smtp -> %>
            <AccountComponents.smtp_card
              source={@smtp_source}
              env_fields={@smtp_env_fields}
              config={@smtp_config}
              form={@smtp_form}
              show_form={@smtp_show_form}
              private_key={@smtp_private_key}
              embedded
            />
          <% :ai -> %>
            <.step_card
              title="Inteligência artificial"
              subtitle="Cadastre um provedor (Gemini, OpenAI, Claude ou compatível) para categorizar gastos e gerar análises."
            >
              <AiComponents.providers_panel
                providers={@ai_providers}
                selected_ref={@ai_selected_ref}
                default_form={@ai_default_form}
                default_model={@ai_default_model}
                models={@ai_models}
                form={@ai_form}
                show_form={@ai_show_form}
              />
            </.step_card>
          <% :open_finance -> %>
            <OpenFinanceComponents.settings_card
              configured={@open_finance_configured}
              credentials_source={@open_finance_credentials_source}
              client_id={@open_finance_client_id}
              credentials_form={@open_finance_credentials_form}
              show_credentials_form={@open_finance_show_credentials_form}
              private_key={@open_finance_private_key}
              connections={@open_finance_connections}
              connecting={@open_finance_connecting}
              syncing={@open_finance_syncing}
              show_item_form={@open_finance_show_item_form}
              item_form={@open_finance_item_form}
            />
          <% :done -> %>
            <.step_card title="Tudo pronto" subtitle="Seu Grana está configurado.">
              <p class="ui-body ui-text-secondary mb-4">
                Envie seus primeiros extratos e faturas na tela de Uploads para começar a ver o painel.
              </p>
              <.button
                id="onboarding-finish"
                type="button"
                variant="primary"
                class="w-full"
                phx-click="finish"
              >
                Ir para o painel <.icon name="hero-arrow-right" class="size-4" />
              </.button>
            </.step_card>
        <% end %>

        <div class="mt-4 flex items-center justify-between">
          <.button
            :if={@step != :appearance}
            id="onboarding-back"
            type="button"
            variant="ghost"
            size="sm"
            icon="hero-arrow-left"
            phx-click="back"
          >
            Voltar
          </.button>
          <span :if={@step == :appearance}></span>
          <div :if={@step != :done} class="flex gap-2">
            <.button
              id="onboarding-skip"
              type="button"
              variant="ghost"
              size="sm"
              phx-click="next"
            >
              Pular
            </.button>
            <%!-- Etapas com formulário: o Continuar envia o form (salva) antes de avançar. --%>
            <.button
              :if={continue_mode(assigns) == :submit}
              id="onboarding-next"
              type="submit"
              form={submit_form_id(@step)}
              variant="primary"
              size="sm"
            >
              Continuar
            </.button>
            <.button
              :if={continue_mode(assigns) != :submit}
              id="onboarding-next"
              type="button"
              variant="primary"
              size="sm"
              disabled={continue_mode(assigns) == :blocked}
              phx-click="next"
            >
              Continuar
            </.button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  defp step_card(assigns) do
    ~H"""
    <div>
      <.page_header title={@title} subtitle={@subtitle} />
      <div class="card bg-base-200 p-6 sm:p-8">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:steps, @steps)
     |> assign(:step, :appearance)}
  end

  @impl true
  def handle_event("next", _params, socket) do
    {:noreply, assign(socket, :step, next_step(socket.assigns.step))}
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, :step, previous_step(socket.assigns.step))}
  end

  def handle_event("finish", _params, socket), do: finish(socket)

  @impl true
  def handle_info(:smtp_saved, socket) do
    {:noreply, assign(socket, :step, next_step(:smtp))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp finish(socket) do
    {:ok, _user} = Accounts.complete_onboarding(socket.assigns.current_scope.user)
    {:noreply, push_navigate(socket, to: ~p"/dashboard")}
  end

  defp step_index(id), do: Enum.find_index(@steps, &(&1.id == id))

  # :submit = o form da etapa salva e avança; :blocked = falta preencher (use Pular).
  defp continue_mode(%{step: :ai, ai_providers: []}), do: :blocked

  defp continue_mode(%{step: :smtp} = assigns) do
    cond do
      assigns.smtp_source == :env and not assigns.smtp_show_form -> :next
      assigns.smtp_source in [:database, :mixed] and not assigns.smtp_show_form -> :next
      assigns.smtp_private_key -> :submit
      true -> :blocked
    end
  end

  defp continue_mode(%{step: :open_finance, open_finance_configured: false}), do: :blocked
  defp continue_mode(_assigns), do: :next

  defp submit_form_id(:smtp), do: "smtp-form"

  defp previous_step(id) do
    @steps |> Enum.at(max(step_index(id) - 1, 0)) |> Map.fetch!(:id)
  end

  defp next_step(id) do
    @steps |> Enum.at(min(step_index(id) + 1, length(@steps) - 1)) |> Map.fetch!(:id)
  end
end
