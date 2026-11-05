defmodule GranaWeb.AccountComponents do
  @moduledoc "Blocos de formulário de conta compartilhados por Configurações e Onboarding."
  use GranaWeb, :html

  @smtp_fields [
    host: {"Servidor", "SMTP_HOST"},
    port: {"Porta", "SMTP_PORT"},
    tls: {"Segurança", "SMTP_TLS"},
    username: {"Usuário", "SMTP_USERNAME"},
    password: {"Senha", "SMTP_PASSWORD"},
    from_name: {"Nome do remetente", "MAIL_FROM_NAME"},
    from_address: {"Email do remetente", "MAIL_FROM_ADDRESS"}
  ]

  attr :source, :atom, required: true, doc: ":env, :database, :mixed ou nil"
  attr :config, :map, default: nil
  attr :env_fields, :list, default: [], doc: "campos que vêm do .env (`:host`, `:password`...)"
  attr :form, :any, required: true
  attr :show_form, :boolean, required: true
  attr :private_key, :boolean, required: true, doc: "CLOAK_KEY própria definida"

  attr :embedded, :boolean,
    default: false,
    doc: "no onboarding: botão só envia o teste; o Continuar da etapa salva (form smtp-form)"

  def smtp_card(assigns) do
    assigns =
      assign(assigns,
        form?: is_nil(assigns.source) or assigns.show_form,
        env_vars:
          for({field, {_label, var}} <- @smtp_fields, field in assigns.env_fields, do: var),
        env_complete?: length(assigns.env_fields) == length(@smtp_fields)
      )

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
      <%= cond do %>
        <% @source in [:database, :mixed] -> %>
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
          <p :if={@source == :mixed} id="smtp-env-caption" class="ui-help">
            Completado pelo <.tag kind="env" />: {Enum.join(@env_vars, ", ")}.
          </p>
          <.confirm_modal
            id="smtp-remove-modal"
            title="Remover o SMTP?"
            confirm="Remover"
            loading="Removendo…"
            on_confirm={JS.push("smtp_remove")}
          >
            <%= if @source == :mixed do %>
              Apaga o que foi salvo nesta tela. O que vem do .env continua valendo.
            <% else %>
              O login volta a pedir só a senha e a recuperação por email deixa de funcionar.
            <% end %>
          </.confirm_modal>
        <% @source == :env and not @show_form -> %>
          <div id="smtp-env" class="flex flex-col gap-2">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-3">
              <.smtp_env_field :for={field <- @env_fields} field={field} />
            </div>
            <div :if={!@env_complete?} class="flex flex-col gap-3 sm:flex-row sm:items-center">
              <p class="ui-help">
                O que não está no .env usa o padrão (porta 587, STARTTLS) ou pode ser completado
                na tela.
              </p>
              <.button
                id="smtp-complete"
                type="button"
                variant="secondary"
                size="sm"
                class="shrink-0"
                phx-click="smtp_toggle_form"
              >
                Completar na tela
              </.button>
            </div>
          </div>
        <% @source == :env -> %>
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <p class="ui-help">Complete na tela o que não está no .env.</p>
            <.button
              id="smtp-complete-cancel"
              type="button"
              variant="ghost"
              size="sm"
              class="shrink-0"
              phx-click="smtp_toggle_form"
            >
              Cancelar
            </.button>
          </div>
        <% @env_fields != [] -> %>
          <.notice id="smtp-incomplete" tone={:warning} title="Falta o servidor">
            O .env define parte do SMTP, mas não o <code>SMTP_HOST</code>. Preencha o servidor
            abaixo ou complete o .env.
          </.notice>
        <% true -> %>
          <.empty_state
            id="smtp-none"
            icon="hero-envelope"
            title="Nenhum SMTP configurado"
            text="O login pede só a senha e a recuperação por email fica indisponível."
          />
      <% end %>

      <.notice
        :if={@form? and !@private_key}
        id="smtp-cloak-key-warning"
        tone={:warning}
        title="Defina uma CLOAK_KEY antes"
      >
        Sem ela a senha do SMTP seria criptografada com a chave de desenvolvimento, que é pública.
        Gere com <code>openssl rand -base64 32</code>, coloque <code>CLOAK_KEY=...</code>
        no ambiente e reinicie o servidor.
      </.notice>

      <.form
        :if={@form? and @private_key}
        for={@form}
        id="smtp-form"
        phx-submit="smtp_save"
        autocomplete="off"
        data-form-type="other"
        class="grid grid-cols-1 sm:grid-cols-2 gap-x-3"
      >
        <.smtp_env_field :if={:host in @env_fields} field={:host} />
        <.input
          :if={:host not in @env_fields}
          field={@form[:smtp_host]}
          type="text"
          label="Servidor"
          placeholder="smtp.exemplo.com"
        />
        <.smtp_env_field :if={:port in @env_fields} field={:port} />
        <.input :if={:port not in @env_fields} field={@form[:smtp_port]} type="number" label="Porta" />
        <.smtp_env_field :if={:tls in @env_fields} field={:tls} />
        <.input
          :if={:tls not in @env_fields}
          field={@form[:smtp_tls]}
          type="select"
          label="Segurança"
          options={[
            {"STARTTLS (recomendado)", "always"},
            {"Se disponível", "if_available"},
            {"Nenhuma", "never"}
          ]}
        />
        <.smtp_env_field :if={:username in @env_fields} field={:username} />
        <.input
          :if={:username not in @env_fields}
          field={@form[:smtp_username]}
          type="text"
          label="Usuário"
          autocomplete="off"
        />
        <.smtp_env_field :if={:password in @env_fields} field={:password} />
        <.input
          :if={:password not in @env_fields}
          field={@form[:smtp_password]}
          type="password"
          label="Senha"
          autocomplete="new-password"
          data-1p-ignore="true"
          data-lpignore="true"
        />
        <.smtp_env_field :if={:from_name in @env_fields} field={:from_name} />
        <.input
          :if={:from_name not in @env_fields}
          field={@form[:smtp_from_name]}
          type="text"
          label="Nome do remetente"
          placeholder="Grana"
        />
        <.smtp_env_field :if={:from_address in @env_fields} field={:from_address} />
        <.input
          :if={:from_address not in @env_fields}
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

  attr :field, :atom, required: true

  defp smtp_env_field(assigns) do
    {label, var} = Keyword.fetch!(@smtp_fields, assigns.field)

    assigns =
      assign(assigns,
        id: "smtp-env-" <> String.replace(to_string(assigns.field), "_", "-"),
        label: label,
        var: var
      )

    ~H"""
    <.env_field id={@id} label={@label} var={@var} secret={@field == :password} />
    """
  end
end
