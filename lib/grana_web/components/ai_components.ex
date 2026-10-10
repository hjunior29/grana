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
    <div id="ai-providers">
      <%!-- Padrão: provedor + modelo usados nas análises e categorizações --%>
      <.form
        :if={@providers != []}
        for={@default_form}
        id="ai-default-form"
        phx-change="ai_default_change"
        phx-submit="ai_save_default"
        class="mb-5 grid grid-cols-1 gap-3 md:grid-cols-2"
      >
        <div>
          <label class="mb-1 block text-sm font-medium" for="ai-default-provider">Provedor</label>
          <select
            id="ai-default-provider"
            name="default[provider]"
            class="select select-bordered w-full"
          >
            <option
              :for={provider <- @providers}
              value={ref(provider)}
              selected={ref(provider) == @selected_ref}
            >
              {provider.name}
            </option>
          </select>
        </div>
        <div>
          <label class="mb-1 block text-sm font-medium" for="ai-default-model">Modelo</label>
          <%= case @model_state do %>
            <% {:ok, models} -> %>
              <select
                id="ai-default-model"
                name="default[model]"
                class="select select-bordered w-full"
              >
                <option
                  :if={@default_model not in [nil | Enum.map(models, & &1.id)]}
                  value={@default_model}
                  selected
                >
                  {@default_model}
                </option>
                <option
                  :for={model <- models}
                  value={model.id}
                  selected={model.id == @default_form[:model].value}
                >
                  {model.name}
                </option>
              </select>
            <% {:error, message} -> %>
              <p id="ai-models-error" class="rounded-lg bg-error/10 px-3 py-2 text-xs text-error">
                {message}
              </p>
            <% _ -> %>
              <div
                id="ai-models-loading"
                class="flex h-12 items-center gap-2 rounded-lg bg-base-100/60 px-3 text-sm opacity-70"
              >
                <span class="loading loading-spinner loading-xs"></span> Carregando modelos…
              </div>
          <% end %>
        </div>
        <div class="md:col-span-2">
          <.button class="btn btn-primary btn-sm" phx-disable-with="Salvando...">
            Salvar padrão
          </.button>
          <span class="ml-2 text-xs opacity-50">
            Modelo usado em análises, categorização e leitura de PDFs.
          </span>
        </div>
      </.form>

      <%!-- Provedores cadastrados --%>
      <h4 class="mb-2 text-sm font-medium opacity-70">Provedores</h4>
      <p :if={@providers == []} id="ai-no-providers" class="mb-3 text-sm opacity-60">
        Nenhum provedor ainda. Cadastre o primeiro abaixo (Gemini, OpenAI, Claude ou qualquer
        serviço compatível) ou defina <code>GEMINI_API_KEY</code>, <code>OPENAI_API_KEY</code>
        ou <code>ANTHROPIC_API_KEY</code>
        no ambiente.
      </p>
      <ul :if={@providers != []} id="ai-provider-list" class="mb-3 divide-y divide-base-content/10">
        <li
          :for={provider <- @providers}
          id={"ai-provider-#{ref(provider)}"}
          class="flex items-center justify-between gap-3 py-2 text-sm"
        >
          <span class="min-w-0">
            <span class="font-medium">{provider.name}</span>
            <span class="block truncate text-xs opacity-50">
              {AI.label(provider.kind)}<span :if={provider.base_url}> · {provider.base_url}</span>
            </span>
          </span>
          <span class="flex shrink-0 items-center gap-2">
            <span :if={provider.source == :env} class="badge badge-info badge-soft badge-sm">
              .env
            </span>
            <span :if={provider.source == :database} class="badge badge-success badge-soft badge-sm">
              chave salva
            </span>
            <button
              :if={provider.source == :database}
              id={"ai-remove-#{provider.id}"}
              type="button"
              phx-click="ai_remove_provider"
              phx-value-id={provider.id}
              data-confirm={"Remover #{provider.name}? A chave salva será apagada."}
              class="btn btn-ghost btn-xs text-error/80"
            >
              Remover
            </button>
          </span>
        </li>
      </ul>

      <button
        :if={!@show_form}
        id="ai-add-provider"
        type="button"
        phx-click="ai_toggle_form"
        class="btn btn-sm"
      >
        <.icon name="hero-plus" class="size-4" /> Adicionar provedor
      </button>

      <.form
        :if={@show_form}
        for={@form}
        id="ai-provider-form"
        phx-change="ai_validate_provider"
        phx-submit="ai_add_provider"
        autocomplete="off"
        data-form-type="other"
        class="mt-2 grid grid-cols-1 gap-x-3 md:grid-cols-2"
      >
        <.input
          field={@form[:kind]}
          type="select"
          label="Tipo"
          options={AI.kinds() |> Enum.map(fn {kind, label} -> {label, kind} end)}
        />
        <.input
          field={@form[:name]}
          type="text"
          label="Nome"
          placeholder={AI.label(@form[:kind].value) || "Nome do provedor"}
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
        <div class="flex items-center gap-2 md:col-span-2">
          <.button class="btn btn-primary btn-sm" phx-disable-with="Verificando...">
            Verificar e adicionar
          </.button>
          <button type="button" phx-click="ai_toggle_form" class="btn btn-ghost btn-sm">
            Cancelar
          </button>
          <span class="text-xs opacity-50">
            A chave é conferida listando os modelos e guardada cifrada.
          </span>
        </div>
      </.form>
    </div>
    """
  end

  defp ref(provider), do: AI.ProviderConfig.ref(provider)
end
