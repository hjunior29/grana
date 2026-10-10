defmodule GranaWeb.AccountComponents do
  @moduledoc "Blocos de formulário de conta compartilhados por Configurações e Onboarding."
  use GranaWeb, :html

  @doc """
  Campo desabilitado para um valor que vem do `.env`: mostra só o nome da variável
  (nunca o valor), com a tag `.env` e um ícone (chave para segredos, documento para o resto).
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :var, :string, required: true, doc: "nome da variável de ambiente"
  attr :secret, :boolean, default: false, doc: "escolhe o ícone: chave para segredos"

  def env_field(assigns) do
    ~H"""
    <div class="mb-2">
      <label class="mb-1 flex items-center gap-2 text-sm font-medium" for={@id}>
        {@label} <span class="badge badge-info badge-soft badge-sm">.env</span>
      </label>
      <div class="relative">
        <.icon
          name={if @secret, do: "hero-key", else: "hero-document-text"}
          class="pointer-events-none absolute left-3 top-1/2 z-10 size-4 -translate-y-1/2 opacity-60"
        />
        <input
          id={@id}
          type="text"
          disabled
          value={@var}
          class="input input-bordered w-full pl-9 font-mono text-sm"
        />
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :env_key, :boolean, required: true, doc: "GEMINI_API_KEY definida no ambiente"
  attr :has_api_key, :boolean, required: true
  attr :show_api_key, :boolean, required: true

  attr :embedded, :boolean,
    default: false,
    doc: "dentro do onboarding: sem botão Salvar; o Continuar da etapa envia o form (id ai_form)"

  def ai_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="ai_form"
      phx-submit={if @embedded, do: "ai_continue", else: "update_ai_settings"}
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
        <div id="ai-api-key-env" class="mb-4">
          <.env_field id="ai-api-key-env-input" label="API Key" secret var="GEMINI_API_KEY" />
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
          <p
            :for={{msg, _} <- @form[:ai_api_key].errors}
            id="ai-api-key-error"
            class="mb-1 text-sm text-error"
          >
            {msg}
          </p>
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
      <.button :if={!@embedded} class="btn btn-primary btn-sm" phx-disable-with="Salvando...">
        Salvar
      </.button>
    </.form>
    """
  end

  attr :source, :atom, required: true, doc: ":env, :database ou nil"
  attr :config, :map, default: nil
  attr :form, :any, required: true
  attr :show_form, :boolean, required: true
  attr :private_key, :boolean, required: true, doc: "CLOAK_KEY própria definida"

  attr :embedded, :boolean,
    default: false,
    doc: "no onboarding: botão só envia o teste; o Continuar da etapa salva (form smtp-form)"

  def smtp_card(assigns) do
    ~H"""
    <div id="smtp-settings" class="card bg-base-200 p-6 mb-6">
      <div class="flex items-center gap-3 mb-1">
        <.icon name="hero-envelope" class="size-5 opacity-60" />
        <h3 class="text-lg font-semibold">Email (SMTP)</h3>
      </div>
      <p class="text-sm opacity-50 mb-5 ml-8">
        Usado para o código de login (2FA), recuperar a senha, confirmar troca de email e
        avisos. Ao configurar, todo login passa a pedir um código de 6 dígitos enviado ao seu email.
      </p>

      <%= case @source do %>
        <% :database -> %>
          <div
            id="smtp-saved"
            class="flex flex-wrap items-center gap-x-2 gap-y-1 rounded-xl bg-base-100/60 px-3 py-2 text-xs"
          >
            <.icon name="hero-server" class="size-4 opacity-60" />
            <code>{@config.host}:{@config.port}</code>
            <span :if={@config.username} class="opacity-60">· {@config.username}</span>
            <span class="badge badge-success badge-soft badge-xs">2FA ativo</span>
            <div class="ml-auto flex gap-1">
              <button
                id="smtp-replace"
                type="button"
                phx-click="smtp_toggle_form"
                class="btn btn-ghost btn-xs"
              >
                Substituir
              </button>
              <button
                id="smtp-remove"
                type="button"
                phx-click="smtp_remove"
                data-confirm="Remover o SMTP? O login volta a pedir só a senha e a recuperação por email deixa de funcionar."
                class="btn btn-ghost btn-xs text-error/80"
              >
                Remover
              </button>
            </div>
          </div>
        <% :env -> %>
          <div id="smtp-env" class="mt-1">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-3">
              <.env_field id="smtp-env-host" label="Servidor" var="SMTP_HOST" />
              <.env_field id="smtp-env-port" label="Porta" var="SMTP_PORT" />
              <.env_field id="smtp-env-tls" label="Segurança" var="SMTP_TLS" />
              <.env_field id="smtp-env-username" label="Usuário" var="SMTP_USERNAME" />
              <.env_field id="smtp-env-password" label="Senha" secret var="SMTP_PASSWORD" />
              <.env_field id="smtp-env-from-name" label="Nome do remetente" var="MAIL_FROM_NAME" />
              <.env_field
                id="smtp-env-from-address"
                label="Email do remetente"
                var="MAIL_FROM_ADDRESS"
              />
            </div>
            <span class="badge badge-success badge-soft badge-sm mt-1">2FA ativo</span>
          </div>
        <% nil -> %>
          <p id="smtp-none" class="text-xs opacity-60">
            Nenhum SMTP configurado: o login pede só a senha e a recuperação por email fica indisponível.
          </p>
      <% end %>

      <div :if={is_nil(@source) or (@source == :database and @show_form)} class="mt-3">
        <div
          :if={!@private_key}
          id="smtp-cloak-key-warning"
          class="rounded-xl border border-warning/40 bg-warning/10 px-3 py-2 text-xs leading-relaxed"
        >
          <p class="font-medium flex items-center gap-1">
            <.icon name="hero-exclamation-triangle" class="size-4" /> Defina uma CLOAK_KEY antes
          </p>
          <p class="opacity-80 mt-1">
            Sem ela a senha do SMTP seria cifrada com a chave de desenvolvimento, que é pública.
            Gere com <code>openssl rand -base64 32</code>, coloque <code>CLOAK_KEY=...</code>
            no ambiente e reinicie o servidor.
          </p>
        </div>

        <.form
          :if={@private_key}
          for={@form}
          id="smtp-form"
          phx-submit="smtp_save"
          autocomplete="off"
          data-form-type="other"
          class="grid grid-cols-1 sm:grid-cols-2 gap-x-3"
        >
          <.input
            field={@form[:smtp_host]}
            type="text"
            label="Servidor"
            placeholder="smtp.exemplo.com"
          />
          <.input field={@form[:smtp_port]} type="number" label="Porta" />
          <.input
            field={@form[:smtp_tls]}
            type="select"
            label="Segurança"
            options={[
              {"STARTTLS (recomendado)", "always"},
              {"Se disponível", "if_available"},
              {"Nenhuma", "never"}
            ]}
          />
          <.input field={@form[:smtp_username]} type="text" label="Usuário" autocomplete="off" />
          <.input
            field={@form[:smtp_password]}
            type="password"
            label="Senha"
            autocomplete="new-password"
            data-1p-ignore="true"
            data-lpignore="true"
          />
          <.input
            field={@form[:smtp_from_name]}
            type="text"
            label="Nome do remetente"
            placeholder="Grana"
          />
          <.input
            field={@form[:smtp_from_address]}
            type="email"
            label="Email do remetente"
            placeholder="grana@exemplo.com"
          />
          <div class="sm:col-span-2 flex flex-wrap items-center gap-3">
            <%= if @embedded do %>
              <.button
                id="smtp-test"
                name="intent"
                value="test"
                class="btn btn-outline btn-sm"
                phx-disable-with="Enviando teste..."
              >
                Enviar teste
              </.button>
              <p class="text-xs opacity-50">
                O teste vai para o seu email e não salva nada. Ao clicar em Continuar, o SMTP é
                testado e salvo (senha cifrada).
              </p>
            <% else %>
              <.button class="btn btn-primary btn-sm" phx-disable-with="Enviando teste...">
                Enviar teste e salvar
              </.button>
              <p class="text-xs opacity-50">
                Enviamos um email de teste para você; só salvamos se ele chegar. A senha é guardada cifrada.
              </p>
            <% end %>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
