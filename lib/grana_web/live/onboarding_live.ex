defmodule GranaWeb.OnboardingLive do
  use GranaWeb, :live_view

  alias Grana.Accounts
  alias GranaWeb.AccountComponents
  alias GranaWeb.OpenFinanceComponents

  on_mount GranaWeb.AiSettingsHooks
  on_mount GranaWeb.SmtpHooks
  on_mount GranaWeb.OpenFinanceHooks

  @steps [
    %{id: :appearance, title: "Aparência", icon: "hero-paint-brush"},
    %{id: :smtp, title: "Email", icon: "hero-envelope"},
    %{id: :ai, title: "IA", icon: "hero-sparkles"},
    %{id: :open_finance, title: "Open Finance", icon: "hero-link"},
    %{id: :import, title: "Importar", icon: "hero-arrow-up-tray"},
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
                else: "bg-base-200 opacity-60"
              )
            ]}
          >
            <.icon name={step.icon} class="size-4" />
          </li>
        </ol>

        <%= case @step do %>
          <% :appearance -> %>
            <.step_card title="Aparência" subtitle="Escolha o tema e o estilo visual do Grana.">
              <p class="text-sm opacity-60">Você pode mudar isso depois em Configurações.</p>
            </.step_card>
          <% :smtp -> %>
            <AccountComponents.smtp_card
              source={@smtp_source}
              config={@smtp_config}
              form={@smtp_form}
              show_form={@smtp_show_form}
              private_key={@smtp_private_key}
            />
          <% :ai -> %>
            <.step_card
              title="Inteligência artificial"
              subtitle="Cole sua chave do Gemini para categorizar gastos e gerar análises."
            >
              <AccountComponents.ai_form
                form={@ai_form}
                env_key={@ai_env_key}
                has_api_key={@has_ai_api_key}
                show_api_key={@show_api_key}
              />
            </.step_card>
          <% :open_finance -> %>
            <OpenFinanceComponents.settings_card
              configured={@open_finance_configured}
              credentials_source={@open_finance_credentials_source}
              client_id={@current_scope.user.pluggy_client_id}
              credentials_form={@open_finance_credentials_form}
              show_credentials_form={@open_finance_show_credentials_form}
              private_key={@open_finance_private_key}
              connections={@open_finance_connections}
              connecting={@open_finance_connecting}
              syncing={@open_finance_syncing}
              show_item_form={@open_finance_show_item_form}
              item_form={@open_finance_item_form}
            />
          <% :import -> %>
            <.step_card
              title="Importar dados"
              subtitle="Já tem um CSV exportado do Grana? Envie aqui para trazer seu histórico."
            >
              <form id="import-form" phx-submit="import" phx-change="validate_import">
                <.live_file_input
                  upload={@uploads.import}
                  class="file-input file-input-bordered w-full mb-3"
                />
                <p
                  :for={entry <- @uploads.import.entries}
                  id={"import-entry-#{entry.ref}"}
                  class="text-sm opacity-70"
                >
                  {entry.client_name}
                </p>
                <.button
                  :if={@uploads.import.entries != []}
                  class="btn btn-primary btn-sm mt-3"
                  phx-disable-with="Enviando..."
                >
                  Importar
                </.button>
              </form>
              <p :if={@imported} id="import-result" class="mt-3 text-sm text-success">
                Importação iniciada — os dados aparecem no painel em instantes.
              </p>
            </.step_card>
          <% :done -> %>
            <.step_card title="Tudo pronto!" subtitle="Seu Grana está configurado.">
              <p class="mb-4 text-sm opacity-70">
                Envie seus primeiros extratos e faturas na tela de Uploads para começar a ver o painel.
              </p>
              <button id="onboarding-finish" phx-click="finish" class="btn btn-primary w-full">
                Ir para o painel <.icon name="hero-arrow-right" class="size-4" />
              </button>
            </.step_card>
        <% end %>

        <div :if={@step != :done} class="mt-4 flex items-center justify-between">
          <button id="onboarding-skip-all" phx-click="skip_all" class="btn btn-ghost btn-sm">
            Pular tudo
          </button>
          <div class="flex gap-2">
            <button id="onboarding-skip" phx-click="next" class="btn btn-ghost btn-sm">
              Pular
            </button>
            <button id="onboarding-next" phx-click="next" class="btn btn-primary btn-sm">
              Continuar
            </button>
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
    <div class="card bg-base-200 p-6 sm:p-8">
      <h1 class="text-2xl font-bold tracking-tight">{@title}</h1>
      <p :if={@subtitle} class="mb-5 mt-1 text-sm opacity-70">{@subtitle}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:steps, @steps)
     |> assign(:step, :appearance)
     |> assign(:imported, false)
     |> allow_upload(:import, accept: ~w(.csv), max_entries: 5, max_file_size: 5_000_000)}
  end

  @impl true
  def handle_event("next", _params, socket) do
    {:noreply, assign(socket, :step, next_step(socket.assigns.step))}
  end

  def handle_event("skip_all", _params, socket), do: finish(socket)
  def handle_event("finish", _params, socket), do: finish(socket)

  def handle_event("validate_import", _params, socket), do: {:noreply, socket}

  def handle_event("import", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    files =
      consume_uploaded_entries(socket, :import, fn %{path: path}, entry ->
        {:ok,
         %{"filename" => entry.client_name, "content_b64" => Base.encode64(File.read!(path))}}
      end)

    %{files: files, user_id: user_id, topic: "onboarding:#{user_id}"}
    |> Grana.Workers.PlatformImportWorker.new()
    |> Oban.insert()

    {:noreply, assign(socket, :imported, true)}
  end

  defp finish(socket) do
    {:ok, _user} = Accounts.complete_onboarding(socket.assigns.current_scope.user)
    {:noreply, push_navigate(socket, to: ~p"/dashboard")}
  end

  defp step_index(id), do: Enum.find_index(@steps, &(&1.id == id))

  defp next_step(id) do
    @steps |> Enum.at(min(step_index(id) + 1, length(@steps) - 1)) |> Map.fetch!(:id)
  end
end
