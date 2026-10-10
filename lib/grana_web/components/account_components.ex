defmodule GranaWeb.AccountComponents do
  @moduledoc "Blocos de formulário de conta compartilhados por Configurações e Onboarding."
  use GranaWeb, :html

  attr :form, :any, required: true
  attr :env_key, :boolean, required: true, doc: "GEMINI_API_KEY definida no ambiente"
  attr :has_api_key, :boolean, required: true
  attr :show_api_key, :boolean, required: true

  def ai_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="ai_form"
      phx-submit="update_ai_settings"
      phx-change="validate_ai_settings"
      autocomplete="off"
      data-form-type="other"
      novalidate
    >
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
        <div>
          <label class="text-sm font-medium block mb-1">Provider</label>
          <select name="user[ai_provider]" class="select select-bordered w-full">
            <option value="gemini" selected={@form[:ai_provider].value == "gemini"}>
              Google Gemini
            </option>
          </select>
        </div>
        <div>
          <label class="text-sm font-medium block mb-1">Modelo</label>
          <select name="user[ai_model]" class="select select-bordered w-full">
            <option
              value="gemini-2.0-flash"
              selected={@form[:ai_model].value == "gemini-2.0-flash"}
            >
              Gemini 2.0 Flash
            </option>
            <option
              value="gemini-2.5-flash"
              selected={@form[:ai_model].value == "gemini-2.5-flash"}
            >
              Gemini 2.5 Flash
            </option>
            <option
              value="gemini-2.5-pro"
              selected={@form[:ai_model].value == "gemini-2.5-pro"}
            >
              Gemini 2.5 Pro
            </option>
          </select>
        </div>
      </div>
      <%= if @env_key do %>
        <div
          id="ai-api-key-env"
          class="mb-4 flex items-center gap-2 rounded-xl bg-base-100/60 px-3 py-2 text-xs"
        >
          <.icon name="hero-key" class="size-4 opacity-60" />
          <span class="opacity-70">
            API key: usando <code>GEMINI_API_KEY</code> do <code>.env</code>.
          </span>
        </div>
      <% else %>
        <div class="mb-4">
          <div class="flex items-center justify-between mb-1">
            <label class="text-sm font-medium">API Key</label>
            <button
              :if={@has_api_key}
              id="remove-ai-api-key"
              type="button"
              phx-click="remove_ai_api_key"
              data-confirm="Remover a API key salva?"
              class="link link-hover text-xs text-error/80"
            >
              Remover chave salva
            </button>
          </div>
          <div class="relative">
            <%!-- Só de escrita: o valor salvo nunca é enviado de volta ao navegador. --%>
            <input
              id="ai-api-key-input"
              type={if @show_api_key, do: "text", else: "password"}
              name="user[ai_api_key]"
              value={@form[:ai_api_key].value}
              placeholder={
                if @has_api_key,
                  do: "•••••••• salva — digite para substituir",
                  else: "Cole sua API key"
              }
              class="input input-bordered w-full pr-12"
              autocomplete="one-time-code"
              data-1p-ignore="true"
              data-lpignore="true"
              data-form-type="other"
            />
            <button
              type="button"
              phx-click="toggle_api_key_visibility"
              class="absolute right-3 top-1/2 -translate-y-1/2 opacity-40 hover:opacity-70 transition-opacity"
            >
              <.icon :if={!@show_api_key} name="hero-eye" class="size-5 cursor-pointer" />
              <.icon :if={@show_api_key} name="hero-eye-slash" class="size-5 cursor-pointer" />
            </button>
          </div>
        </div>
      <% end %>
      <.button class="btn btn-primary btn-sm" phx-disable-with="Salvando...">Salvar</.button>
    </.form>
    """
  end
end
