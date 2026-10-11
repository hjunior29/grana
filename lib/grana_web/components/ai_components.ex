defmodule GranaWeb.AiComponents do
  @moduledoc "Painel de provedores de IA (estado em `GranaWeb.AiSettingsHooks`)."
  use GranaWeb, :html

  alias Grana.AI

  attr :providers, :list, required: true
  attr :selected_ref, :string, default: nil
  attr :default_form, :any, required: true
  attr :default_model, :string, default: nil
  attr :models, :map, required: true, doc: "ref => :loading | {:ok, lista} | {:error, msg}"
  attr :form, :any, required: true
  attr :show_form, :boolean, required: true

  def providers_panel(assigns) do
    assigns = assign(assigns, :model_state, assigns.models[assigns.selected_ref])

    ~H"""
    <div id="ai-providers" class="flex flex-col gap-6">
      <%!-- Padrão: provedor + modelo usados nas análises e categorizações --%>
      <.form
        :if={@providers != []}
        for={@default_form}
        id="ai-default-form"
        phx-change="ai_default_change"
        phx-submit="ai_save_default"
        class="grid grid-cols-1 gap-x-3 md:grid-cols-2"
      >
        <.input
          id="ai-default-provider"
          type="select"
          name="default[provider]"
          label="Provedor"
          value={@selected_ref}
          options={Enum.map(@providers, &{&1.name, ref(&1)})}
        />
        <%= case @model_state do %>
          <% {:ok, models} -> %>
            <.input
              id="ai-default-model"
              field={@default_form[:model]}
              type="select"
              label="Modelo"
              value={@default_form[:model].value || @default_model}
              options={model_options(models, @default_model)}
            />
          <% {:error, message} -> %>
            <div>
              <span class="ui-label">Modelo</span>
              <.notice id="ai-models-error" tone={:error}>{message}</.notice>
            </div>
          <% _ -> %>
            <div>
              <span class="ui-label">Modelo</span>
              <div
                id="ai-models-loading"
                class="ui-rounded-field ui-body ui-text-secondary flex h-10 items-center gap-2 bg-base-100/60 px-3"
              >
                <span class="loading loading-spinner loading-xs"></span> Carregando modelos…
              </div>
            </div>
        <% end %>
        <div class="mt-2 flex flex-col gap-3 md:col-span-2 sm:flex-row sm:items-center">
          <.button variant="primary" size="sm" class="w-full sm:w-auto" loading="Salvando…">
            Salvar padrão
          </.button>
          <p class="ui-help">Modelo usado em análises, categorização e leitura de PDFs.</p>
        </div>
      </.form>

      <%!-- Provedores cadastrados --%>
      <.section title="Provedores">
        <.empty_state
          :if={@providers == []}
          id="ai-no-providers"
          icon="hero-cpu-chip"
          title="Nenhum provedor ainda"
          text="Cadastre o primeiro abaixo (Gemini, OpenAI, Claude ou qualquer serviço compatível) ou defina GEMINI_API_KEY, OPENAI_API_KEY ou ANTHROPIC_API_KEY no ambiente."
        />
        <ul :if={@providers != []} id="ai-provider-list" class="divide-y divide-base-content/10">
          <.item_row
            :for={provider <- @providers}
            id={"ai-provider-#{ref(provider)}"}
            title={provider.name}
            subtitle={provider_subtitle(provider)}
          >
            <:tags>
              <.tag :if={provider.source == :env} kind="env" />
              <.tag :if={provider.source == :database} kind="salvo" />
            </:tags>
            <:actions>
              <.button
                :if={provider.source == :database}
                id={"ai-remove-#{provider.id}"}
                type="button"
                variant="ghost"
                size="sm"
                class="text-error"
                phx-click={show_modal("ai-remove-modal-#{provider.id}")}
              >
                Remover
              </.button>
            </:actions>
          </.item_row>
        </ul>
        <%= for provider <- @providers, provider.source == :database do %>
          <.confirm_modal
            id={"ai-remove-modal-#{provider.id}"}
            title={"Remover #{provider.name}?"}
            confirm="Remover"
            loading="Removendo…"
            on_confirm={JS.push("ai_remove_provider", value: %{id: to_string(provider.id)})}
          >
            A chave salva será apagada.
          </.confirm_modal>
        <% end %>

        <div :if={!@show_form} class="mt-3">
          <.button
            id="ai-add-provider"
            type="button"
            variant="secondary"
            size="sm"
            icon="hero-plus"
            phx-click="ai_toggle_form"
          >
            Adicionar provedor
          </.button>
        </div>
      </.section>

      <.form
        :if={@show_form}
        for={@form}
        id="ai-provider-form"
        phx-change="ai_validate_provider"
        phx-submit="ai_add_provider"
        autocomplete="off"
        data-form-type="other"
        class="grid grid-cols-1 gap-x-3 md:grid-cols-2"
      >
        <.input
          field={@form[:kind]}
          type="select"
          label="Tipo"
          options={AI.kinds() |> Enum.map(fn {kind, label} -> {label, kind} end)}
        />
        <%!-- Só os compatíveis têm nome livre; nos demais, o nome é o do próprio provedor. --%>
        <.input
          :if={@form[:kind].value == "openai_compatible"}
          field={@form[:name]}
          type="text"
          label="Nome"
          placeholder="Ex.: OpenRouter, Ollama"
        />
        <div :if={@form[:kind].value == "openai_compatible"} class="md:col-span-2">
          <.input
            field={@form[:base_url]}
            type="text"
            label="Endereço da API"
            placeholder="https://openrouter.ai/api/v1"
          />
        </div>
        <div class="md:col-span-2">
          <.input
            field={@form[:api_key]}
            type="password"
            label={
              if @form[:kind].value == "openai_compatible",
                do: "Chave da API (opcional em serviços locais)",
                else: "Chave da API"
            }
            autocomplete="new-password"
            data-1p-ignore="true"
            data-lpignore="true"
          />
        </div>
        <div class="mt-2 flex flex-col gap-3 md:col-span-2 sm:flex-row sm:items-center">
          <div class="flex shrink-0 gap-2">
            <.button
              variant="primary"
              size="sm"
              class="flex-1 sm:flex-none"
              loading="Verificando…"
            >
              Verificar e adicionar
            </.button>
            <.button type="button" variant="ghost" size="sm" phx-click="ai_toggle_form">
              Cancelar
            </.button>
          </div>
          <p class="ui-help">A chave é conferida listando os modelos e guardada criptografada.</p>
        </div>
      </.form>
    </div>
    """
  end

  defp provider_subtitle(provider) do
    [AI.label(provider.kind), provider.base_url] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  # Mantém o modelo salvo no select mesmo quando a API não o lista mais.
  defp model_options(models, default_model) do
    listed = Enum.map(models, &{&1.name, &1.id})

    if default_model in [nil | Enum.map(models, & &1.id)],
      do: listed,
      else: [{default_model, default_model} | listed]
  end

  defp ref(provider), do: AI.ProviderConfig.ref(provider)
end
