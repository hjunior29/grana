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
          <p class="ui-help">Padrão geral: vale para todo especialista sem um modelo próprio.</p>
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

  @specialists [
    {"search", "Pesquisa avançada", "Monta a busca a partir do que você pede em português."},
    {"analysis", "Análise", "Gera as análises do mês ou do ano."},
    {"processing", "Processamento", "Lê PDFs e categoriza o que as regras não pegaram."},
    {"chat", "Chat", "Conduz a conversa e consulta os seus dados."}
  ]

  @doc "Default model of each specialist; blank follows the general default."
  attr :choices, :any, required: true, doc: ":loading or the list of `Grana.AI.model_choices/1`"
  attr :general, :any, default: nil, doc: "{provider, model} of the general default"
  attr :values, :map, required: true, doc: "specialist => saved choice"

  def specialists_panel(assigns) do
    assigns = assign(assigns, :specialists, @specialists)

    ~H"""
    <.section id="ai-specialists" title="Modelo por especialista" divider>
      <p class="ui-help -mt-1 mb-4">
        Cada ação de IA tem um especialista. Escolha o modelo padrão de cada um; na hora de usar, dá para trocar só naquela vez.
      </p>
      <.form for={%{}} as={:specialists} id="ai-specialists-form" phx-submit="ai_save_specialists">
        <div class="grid grid-cols-1 gap-x-4 gap-y-1 md:grid-cols-2">
          <div :for={{key, label, help} <- @specialists} class="fieldset mb-2">
            <label for={"ai-specialist-#{key}"} class="ui-label">{label}</label>
            <select id={"ai-specialist-#{key}"} name={"specialists[#{key}]"} class="w-full select">
              {Phoenix.HTML.Form.options_for_select(
                specialist_options(@choices, @general, @values[key], key),
                @values[key] || ""
              )}
            </select>
            <p class="ui-help mt-1">{help}</p>
          </div>
        </div>
        <div class="mt-2 flex flex-col gap-3 sm:flex-row sm:items-center">
          <.button variant="primary" size="sm" class="w-full sm:w-auto" loading="Salvando…">
            Salvar especialistas
          </.button>
          <p :if={@choices == :loading} class="ui-help flex items-center gap-2">
            <span class="loading loading-spinner loading-xs"></span> Carregando modelos…
          </p>
        </div>
      </.form>
    </.section>
    """
  end

  defp specialist_options(choices, general, saved, key) do
    general_label =
      case general do
        {_provider, model} -> "Padrão geral · #{model}"
        nil -> "Padrão geral"
      end

    [_default | groups] = picker_options(choices, nil, key == "processing")
    listed = for {_provider, options} <- groups, {_label, value} <- options, do: value

    # Keeps the saved choice selectable while the models load or when the API stops listing it.
    saved_option =
      if saved in [nil | listed],
        do: [],
        else: [{saved |> String.split("|", parts: 2) |> List.last(), saved}]

    [{general_label, ""} | saved_option] ++ groups
  end

  @doc """
  Compact AI model picker. The first option keeps the specialist default (`default`,
  `{provider, model}`); the others are `Grana.AI.choice/2` values grouped by provider.
  """
  attr :id, :string, required: true
  attr :name, :string, default: "model"
  attr :choices, :any, required: true, doc: ":loading or the list of `Grana.AI.model_choices/1`"
  attr :default, :any, default: nil
  attr :value, :string, default: ""
  attr :pdf, :boolean, default: false, doc: "only models that read PDF files (processing)"
  attr :rest, :global

  def model_picker(assigns) do
    ~H"""
    <label class="ui-model-picker" title="Modelo de IA">
      <.icon name="hero-cpu-chip" class="size-4 shrink-0" />
      <span class="sr-only">Modelo de IA</span>
      <select id={@id} name={@name} {@rest}>
        {Phoenix.HTML.Form.options_for_select(picker_options(@choices, @default, @pdf), @value)}
      </select>
    </label>
    """
  end

  defp picker_options(choices, default, pdf?) do
    groups =
      for %{ref: ref, name: name, models: {:ok, models}} <- List.wrap(choices),
          models = if(pdf?, do: AI.Models.for_pdf(models), else: models),
          models != [] do
        {name, Enum.map(models, &{&1.name, AI.choice(ref, &1.id)})}
      end

    [{default_label(default), ""} | groups]
  end

  defp default_label({_provider, model}), do: "Padrão · #{model}"
  defp default_label(nil), do: "Padrão"

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
