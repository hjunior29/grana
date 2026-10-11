defmodule GranaWeb.AccountComponents do
  @moduledoc "Blocos de formulário de conta compartilhados por Configurações e Onboarding."
  use GranaWeb, :html

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
    <.card
      id="smtp-settings"
      icon="hero-envelope"
      title="Email (SMTP)"
      description="Usado para o código de login (2FA), recuperar a senha, confirmar troca de email e avisos. Ao configurar, todo login passa a pedir um código de 6 dígitos enviado ao seu email."
    >
      <:aside>
        <.tag :if={@source} id="smtp-2fa" kind="ativo">2FA ativo</.tag>
        <.tag :if={!@source} id="smtp-2fa" kind="neutro">2FA desativado</.tag>
      </:aside>
      <%= case @source do %>
        <% :database -> %>
          <ul class="divide-y divide-base-content/10">
            <.item_row
              id="smtp-saved"
              title={"#{@config.host}:#{@config.port}"}
              subtitle={@config.username}
            >
              <:leading><.icon name="hero-server" class="size-5 shrink-0" /></:leading>
              <:actions>
                <.button
                  id="smtp-replace"
                  type="button"
                  variant="ghost"
                  size="sm"
                  phx-click="smtp_toggle_form"
                >
                  Substituir
                </.button>
                <.button
                  id="smtp-remove"
                  type="button"
                  variant="ghost"
                  size="sm"
                  class="text-error"
                  phx-click={show_modal("smtp-remove-modal")}
                >
                  Remover
                </.button>
              </:actions>
            </.item_row>
          </ul>
          <.confirm_modal
            id="smtp-remove-modal"
            title="Remover o SMTP?"
            confirm="Remover"
            loading="Removendo…"
            on_confirm={JS.push("smtp_remove")}
          >
            O login volta a pedir só a senha e a recuperação por email deixa de funcionar.
          </.confirm_modal>
        <% :env -> %>
          <div id="smtp-env" class="flex flex-col gap-2">
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
          </div>
        <% nil -> %>
          <.empty_state
            id="smtp-none"
            icon="hero-envelope"
            title="Nenhum SMTP configurado"
            text="O login pede só a senha e a recuperação por email fica indisponível."
          />
      <% end %>

      <.notice
        :if={(is_nil(@source) or (@source == :database and @show_form)) and !@private_key}
        id="smtp-cloak-key-warning"
        tone={:warning}
        title="Defina uma CLOAK_KEY antes"
      >
        Sem ela a senha do SMTP seria criptografada com a chave de desenvolvimento, que é pública.
        Gere com <code>openssl rand -base64 32</code>, coloque <code>CLOAK_KEY=...</code>
        no ambiente e reinicie o servidor.
      </.notice>

      <.form
        :if={(is_nil(@source) or (@source == :database and @show_form)) and @private_key}
        for={@form}
        id="smtp-form"
        phx-submit="smtp_save"
        autocomplete="off"
        data-form-type="other"
        class="grid grid-cols-1 sm:grid-cols-2 gap-x-3"
      >
        <.input field={@form[:smtp_host]} type="text" label="Servidor" placeholder="smtp.exemplo.com" />
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
        <div class="sm:col-span-2 mt-2 flex flex-col gap-3 sm:flex-row sm:items-center">
          <%= if @embedded do %>
            <.button
              id="smtp-test"
              name="intent"
              value="test"
              variant="secondary"
              size="sm"
              class="w-full sm:w-auto"
              loading="Enviando teste…"
            >
              Enviar teste
            </.button>
            <p class="ui-help">
              O teste vai para o seu email e não salva nada. Ao clicar em Continuar, o SMTP é
              testado e salvo (senha criptografada).
            </p>
          <% else %>
            <.button
              variant="primary"
              size="sm"
              class="w-full sm:w-auto"
              loading="Enviando teste…"
            >
              Enviar teste e salvar
            </.button>
            <p class="ui-help">
              Enviamos um email de teste para você; só salvamos se ele chegar. A senha é guardada criptografada.
            </p>
          <% end %>
        </div>
      </.form>
    </.card>
    """
  end
end
