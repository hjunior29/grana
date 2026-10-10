defmodule GranaWeb.OpenFinanceComponents do
  @moduledoc """
  Componentes da integração Open Finance (Pluggy): o card de Configurações e a
  aba Open Finance do Dashboard.
  """
  use GranaWeb, :html

  alias Grana.OpenFinance.Account

  @doc "Card de Configurações: credenciais, conexões, botão do widget e itemId manual."
  attr :configured, :boolean, required: true
  attr :credentials_source, :atom, required: true, doc: ":database, :env ou nil"
  attr :client_id, :string, default: nil
  attr :credentials_form, :any, required: true
  attr :show_credentials_form, :boolean, required: true
  attr :private_key, :boolean, required: true, doc: "CLOAK_KEY própria definida"
  attr :connections, :list, required: true
  attr :connecting, :boolean, required: true
  attr :syncing, :any, required: true, doc: "MapSet com os ids sincronizando"
  attr :show_item_form, :boolean, required: true
  attr :item_form, :any, required: true

  def settings_card(assigns) do
    ~H"""
    <div id="open-finance-settings" class="card bg-base-200 p-6 mb-6">
      <div class="flex items-center gap-3 mb-1">
        <.open_finance_logo class="size-5 shrink-0" />
        <div class="flex items-center gap-1.5">
          <h3 class="text-lg font-semibold">Open Finance</h3>
          <span class="badge badge-ghost badge-sm gap-1.5">
            via <img src={~p"/images/pluggy-logo.png"} alt="Pluggy" class="h-3 w-auto" />
          </span>
        </div>
      </div>
      <p class="text-sm opacity-50 mb-5 ml-8">
        Saldos, cartões e transações lidos direto dos seus bancos, com o consentimento do
        Open Finance Brasil. Por enquanto ficam separados das faturas e extratos importados.
      </p>

      <.credentials
        source={@credentials_source}
        client_id={@client_id}
        form={@credentials_form}
        show_form={@show_credentials_form}
        private_key={@private_key}
      />

      <%= if @configured do %>
        <div
          id="pluggy-connect-widget"
          phx-hook="PluggyConnectWidget"
          phx-update="ignore"
          class="hidden"
        >
        </div>

        <div id="open-finance-connections" class="flex flex-col gap-2 mb-5">
          <div
            :if={@connections == []}
            id="open-finance-empty"
            class="rounded-xl border border-dashed border-base-content/15 px-4 py-6 text-center"
          >
            <.icon name="hero-link" class="size-6 opacity-30 mx-auto mb-2" />
            <p class="text-sm opacity-70">Nenhum banco conectado ainda.</p>
            <p class="text-xs opacity-50 mt-1">
              Conecte pelo Meu Pluggy abaixo — cada banco autorizado lá vira uma conexão aqui.
            </p>
          </div>

          <.connection_row
            :for={connection <- @connections}
            connection={connection}
            syncing={MapSet.member?(@syncing, connection.id)}
          />
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <button
            id="connect-meu-pluggy"
            type="button"
            phx-click="open_finance_connect"
            disabled={@connecting}
            class="btn btn-primary btn-sm gap-2 transition-transform active:scale-[0.98]"
          >
            <span :if={@connecting} class="loading loading-spinner loading-xs"></span>
            <.icon :if={!@connecting} name="hero-plus" class="size-4" />
            {if @connecting, do: "Abrindo widget...", else: "Conectar via Meu Pluggy"}
          </button>
          <button
            id="toggle-item-form"
            type="button"
            phx-click="open_finance_toggle_item_form"
            class="btn btn-ghost btn-sm"
          >
            Tenho o itemId
          </button>
        </div>

        <.form
          :if={@show_item_form}
          for={@item_form}
          id="open-finance-item-form"
          phx-submit="open_finance_add_item"
          class="mt-4"
        >
          <div class="flex flex-col sm:flex-row gap-2 sm:items-start">
            <div class="flex-1 min-w-0 sm:max-w-sm">
              <.input
                field={@item_form[:item_id]}
                type="text"
                placeholder="itemId (UUID)"
                class="input input-sm w-full font-mono"
                autocomplete="off"
                spellcheck="false"
              />
            </div>
            <%!-- pt-1 compensa o respiro do fieldset do <.input>, alinhando os botões ao campo. --%>
            <div class="flex gap-2 sm:pt-1">
              <.button class="btn btn-primary btn-sm" phx-disable-with="Verificando...">
                Adicionar
              </.button>
              <button
                id="cancel-item-form"
                type="button"
                phx-click="open_finance_toggle_item_form"
                class="btn btn-ghost btn-sm"
              >
                Cancelar
              </button>
            </div>
          </div>
          <p class="text-xs opacity-50">
            No dashboard da Pluggy: Aplicações → sua aplicação → Demo → Itens Conectados.
          </p>
        </.form>

        <p class="text-xs opacity-50 mt-4 leading-relaxed">
          No widget, entre com a sua conta do Meu Pluggy e escolha um banco. Para outro banco,
          conecte de novo. Quer só testar?
          <button
            id="connect-sandbox"
            type="button"
            phx-click="open_finance_connect"
            phx-value-sandbox="true"
            class="link link-hover"
          >
            Use o Sandbox
          </button>
          (usuário <code>user-ok</code>, senha <code>password-ok</code>).
        </p>
      <% end %>
    </div>
    """
  end

  attr :source, :atom, required: true
  attr :client_id, :string, default: nil
  attr :form, :any, required: true
  attr :show_form, :boolean, required: true
  attr :private_key, :boolean, required: true

  defp credentials(assigns) do
    ~H"""
    <div id="open-finance-credentials" class="mb-5">
      <%= case @source do %>
        <% :database -> %>
          <div
            id="credentials-saved"
            class="flex flex-wrap items-center gap-x-2 gap-y-1 rounded-xl bg-base-100/60 px-3 py-2 text-xs"
          >
            <.icon name="hero-key" class="size-4 opacity-60" />
            <span class="opacity-60">Client ID</span>
            <code class="truncate max-w-[14rem]">{@client_id}</code>
            <span class="opacity-60">· Secret</span>
            <code>••••••••</code>
            <span class="badge badge-success badge-soft badge-xs">cifrado</span>
            <div class="ml-auto flex gap-1">
              <button
                id="replace-credentials"
                type="button"
                phx-click="open_finance_toggle_credentials_form"
                class="btn btn-ghost btn-xs"
              >
                Substituir
              </button>
              <button
                id="remove-credentials"
                type="button"
                phx-click="open_finance_remove_credentials"
                data-confirm="Apagar as credenciais da Pluggy salvas no Grana? As conexões ficam, mas param de sincronizar até você informar credenciais de novo."
                class="btn btn-ghost btn-xs text-error/80"
              >
                Remover
              </button>
            </div>
          </div>
        <% :env -> %>
          <div
            id="credentials-env"
            class="flex flex-wrap items-center gap-2 rounded-xl bg-base-100/60 px-3 py-2 text-xs"
          >
            <.icon name="hero-key" class="size-4 opacity-60" />
            <span class="opacity-70">
              Usando <code>PLUGGY_CLIENT_ID</code>/<code>PLUGGY_CLIENT_SECRET</code> do <code>.env</code>.
            </span>
          </div>
        <% nil -> %>
          <.setup_steps />
      <% end %>

      <div :if={is_nil(@source) or (@source == :database and @show_form)} class="mt-3">
        <div
          :if={!@private_key}
          id="cloak-key-warning"
          class="rounded-xl border border-warning/40 bg-warning/10 px-3 py-2 text-xs leading-relaxed"
        >
          <p class="font-medium flex items-center gap-1">
            <.icon name="hero-exclamation-triangle" class="size-4" /> Defina uma CLOAK_KEY antes
          </p>
          <p class="opacity-80 mt-1">
            Sem ela o Grana cifra com a chave de desenvolvimento, que é pública no repositório. Gere
            com <code>openssl rand -base64 32</code>, coloque <code>CLOAK_KEY=...</code>
            no <code>.env</code>
            e reinicie o servidor.
          </p>
        </div>

        <.form
          :if={@private_key}
          for={@form}
          id="pluggy-credentials-form"
          phx-submit="open_finance_save_credentials"
          autocomplete="off"
          data-form-type="other"
          class="grid grid-cols-1 sm:grid-cols-2 gap-x-3"
        >
          <.input
            field={@form[:pluggy_client_id]}
            type="text"
            label="Client ID"
            placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
            autocomplete="off"
            spellcheck="false"
          />
          <.input
            field={@form[:pluggy_client_secret]}
            type="password"
            label="Client Secret"
            autocomplete="new-password"
            data-1p-ignore="true"
            data-lpignore="true"
          />
          <div class="sm:col-span-2 flex flex-wrap items-center gap-3">
            <.button class="btn btn-primary btn-sm" phx-disable-with="Verificando na Pluggy...">
              Salvar e verificar
            </.button>
            <p class="text-xs opacity-50">
              Conferido na Pluggy e guardado cifrado — o secret nunca volta para esta tela.
            </p>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :connection, :map, required: true
  attr :syncing, :boolean, required: true

  defp connection_row(assigns) do
    ~H"""
    <div
      id={"connection-#{@connection.id}"}
      class="flex items-center gap-3 rounded-xl bg-base-100/60 px-3 py-2.5 transition-colors hover:bg-base-100"
    >
      <img
        :if={@connection.connector_image_url}
        src={@connection.connector_image_url}
        alt=""
        class="size-9 rounded-lg bg-base-100 object-contain p-1 shrink-0"
      />
      <div
        :if={!@connection.connector_image_url}
        class="size-9 rounded-lg bg-base-100 grid place-items-center shrink-0"
      >
        <.icon name="hero-building-library" class="size-5 opacity-50" />
      </div>

      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2 flex-wrap">
          <span class="text-sm font-medium truncate">
            {@connection.connector_name || "Conexão"}
          </span>
          <.status_badge
            status={@connection.status}
            execution_status={@connection.execution_status}
          />
        </div>
        <p class="text-xs opacity-60 truncate">{accounts_summary(@connection.accounts)}</p>
        <p :if={@connection.sync_error} class="text-xs text-error mt-0.5">
          {@connection.sync_error}
        </p>
        <p :if={!@connection.sync_error} class="text-xs opacity-40 mt-0.5">
          {sync_label(@syncing, @connection.last_synced_at)}
        </p>
      </div>

      <div class="flex items-center gap-1 shrink-0">
        <button
          id={"sync-connection-#{@connection.id}"}
          type="button"
          phx-click="open_finance_sync"
          phx-value-id={@connection.id}
          disabled={@syncing}
          class="btn btn-ghost btn-sm btn-square"
          title="Sincronizar agora"
        >
          <.icon name="hero-arrow-path" class={["size-4", @syncing && "animate-spin"]} />
        </button>
        <button
          id={"remove-connection-#{@connection.id}"}
          type="button"
          phx-click="open_finance_remove"
          phx-value-id={@connection.id}
          data-confirm="Remover esta conexão? O acesso do Grana a ela é revogado na Pluggy e os dados importados dela são apagados. Sua conexão no Meu Pluggy continua intacta."
          class="btn btn-ghost btn-sm btn-square text-error/70 hover:text-error"
          title="Remover conexão"
        >
          <.icon name="hero-trash" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  defp setup_steps(assigns) do
    ~H"""
    <div id="open-finance-setup">
      <p class="text-sm mb-3">Para ativar (uso pessoal, gratuito, até 5 conexões):</p>
      <ol class="list-decimal ml-5 space-y-2 text-sm opacity-80">
        <li>
          Crie sua conta no
          <a href="https://meu.pluggy.ai" target="_blank" rel="noopener" class="link">
            Meu Pluggy
          </a>
          e conecte seus bancos lá (cada banco é autorizado no app do próprio banco).
        </li>
        <li>
          Entre no
          <a href="https://dashboard.pluggy.ai" target="_blank" rel="noopener" class="link">
            dashboard da Pluggy
          </a>
          com a mesma conta e copie o Client ID e o Client Secret em <em>Applications</em>.
        </li>
        <li>
          Cole abaixo. (Se preferir, defina <code>PLUGGY_CLIENT_ID</code>
          e <code>PLUGGY_CLIENT_SECRET</code>
          no <code>.env</code>.)
        </li>
      </ol>
    </div>
    """
  end

  @doc """
  Aba Open Finance do Dashboard: totais, contas/cartões e transações da conta
  escolhida. Somente leitura e separada das faturas/extratos importados.
  """
  attr :configured, :boolean, required: true
  attr :accounts, :list, required: true
  attr :totals, :map, required: true
  attr :selected_account, :any, required: true
  attr :transactions, :any, required: true, doc: "stream das transações da conta escolhida"
  attr :transactions_count, :integer, required: true
  attr :has_more, :boolean, required: true
  attr :syncing, :boolean, required: true

  def overview(assigns) do
    ~H"""
    <div id="open-finance-tab">
      <div class="flex flex-col sm:flex-row sm:items-center gap-3 mb-6">
        <p class="text-xs sm:text-sm opacity-60 flex-1">
          Dados lidos direto dos seus bancos via Pluggy — separados das faturas e extratos importados.
        </p>
        <div class="flex items-center gap-2">
          <button
            :if={@accounts != []}
            id="sync-all"
            type="button"
            phx-click="of_sync_all"
            disabled={@syncing}
            class="btn btn-sm btn-primary gap-2"
          >
            <.icon name="hero-arrow-path" class={["size-4", @syncing && "animate-spin"]} />
            {if @syncing, do: "Sincronizando...", else: "Sincronizar"}
          </button>
          <.link navigate={~p"/users/settings"} class="btn btn-sm btn-ghost gap-1">
            <.icon name="hero-cog-6-tooth" class="size-4" /> Conexões
          </.link>
        </div>
      </div>

      <%= if @accounts == [] do %>
        <div id="open-finance-empty-state" class="card bg-base-200 p-10 text-center">
          <.icon name="hero-building-library" class="size-10 opacity-30 mx-auto mb-3" />
          <h2 class="text-lg font-semibold">Nenhuma conta por aqui ainda</h2>
          <p class="text-sm opacity-60 mt-1 max-w-md mx-auto">
            <%= if @configured do %>
              Conecte seus bancos pelo Meu Pluggy em Configurações. Se você acabou de
              conectar, a importação pode levar alguns segundos.
            <% else %>
              A integração com a Pluggy ainda não foi configurada. O passo a passo está em Configurações.
            <% end %>
          </p>
          <.link navigate={~p"/users/settings"} class="btn btn-primary btn-sm mt-5 mx-auto">
            Ir para Configurações
          </.link>
        </div>
      <% else %>
        <div id="open-finance-summary" class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
          <div class="stat bg-base-200 rounded-xl p-4">
            <div class="stat-title text-xs">Saldo em contas</div>
            <div class="stat-value text-lg sm:text-xl">{format_money(@totals.bank)}</div>
            <div class="stat-desc text-xs">{@totals.bank_count} conta(s)</div>
          </div>
          <div class="stat bg-base-200 rounded-xl p-4">
            <div class="stat-title text-xs">Fatura atual dos cartões</div>
            <div class="stat-value text-lg sm:text-xl text-warning">
              {format_money(@totals.card_used)}
            </div>
            <div class="stat-desc text-xs">{@totals.card_count} cartão(ões)</div>
          </div>
          <div class="stat bg-base-200 rounded-xl p-4">
            <div class="stat-title text-xs">Limite disponível</div>
            <div class="stat-value text-lg sm:text-xl text-success">
              {format_money(@totals.card_available)}
            </div>
            <div class="stat-desc text-xs">somando todos os cartões</div>
          </div>
        </div>

        <div id="open-finance-accounts" class="grid grid-cols-1 md:grid-cols-2 gap-3 mb-8">
          <.account_card
            :for={account <- @accounts}
            account={account}
            selected={@selected_account && account.id == @selected_account.id}
          />
        </div>

        <div :if={@selected_account} id="open-finance-transactions-panel" class="card bg-base-200">
          <div class="px-4 sm:px-5 pt-4 pb-3 min-w-0">
            <h2 class="font-semibold truncate">{account_name(@selected_account)}</h2>
            <p class="text-xs opacity-50">
              {@transactions_count} transação(ões) nos últimos 12 meses
            </p>
          </div>

          <div
            id="open-finance-transactions"
            phx-update="stream"
            class="divide-y divide-base-content/5"
          >
            <div
              id="open-finance-transactions-empty"
              class="hidden only:block px-5 py-10 text-center text-sm opacity-50"
            >
              Nenhuma transação nesta conta.
            </div>
            <div
              :for={{dom_id, transaction} <- @transactions}
              id={dom_id}
              class="flex items-center gap-3 px-4 sm:px-5 py-3 transition-colors hover:bg-base-100/50"
            >
              <div class="w-20 shrink-0 text-xs opacity-60 tabular-nums">
                {format_date(transaction.date)}
              </div>
              <div class="min-w-0 flex-1">
                <p class="text-sm truncate">{transaction.description}</p>
                <div class="flex flex-wrap gap-1 mt-0.5">
                  <span :if={transaction.status == "PENDING"} class="badge badge-warning badge-xs">
                    Pendente
                  </span>
                  <span :if={transaction.operation_type} class="badge badge-ghost badge-xs">
                    {transaction.operation_type}
                  </span>
                  <span :if={transaction.total_installments} class="badge badge-ghost badge-xs">
                    Parcela {transaction.installment_number}/{transaction.total_installments}
                  </span>
                  <span :if={transaction.category} class="text-xs opacity-40 truncate">
                    {transaction.category}
                  </span>
                </div>
              </div>
              <div class={[
                "text-sm font-mono font-semibold whitespace-nowrap",
                if(transaction.type == "CREDIT", do: "text-success", else: "text-error")
              ]}>
                {signed_amount(transaction)}
              </div>
            </div>
          </div>

          <div :if={@has_more} class="p-4 text-center border-t border-base-content/5">
            <button
              id="load-more-transactions"
              type="button"
              phx-click="of_load_more"
              class="btn btn-ghost btn-sm"
            >
              Carregar mais
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :account, Account, required: true
  attr :selected, :boolean, required: true

  defp account_card(assigns) do
    ~H"""
    <.link
      id={"account-#{@account.id}"}
      patch={~p"/dashboard?#{[tab: "open_finance", account: @account.id]}"}
      class={[
        "card bg-base-200 p-4 text-left transition-all hover:-translate-y-0.5 hover:shadow-md",
        @selected && "ring-2 ring-primary/60"
      ]}
    >
      <div class="flex items-center gap-2 mb-3">
        <img
          :if={@account.connection.connector_image_url}
          src={@account.connection.connector_image_url}
          alt=""
          class="size-6 rounded-md bg-base-100 object-contain p-0.5"
        />
        <span class="text-xs opacity-60 truncate flex-1">
          {@account.connection.connector_name} · {account_kind(@account)}
        </span>
        <.status_badge
          status={@account.connection.status}
          execution_status={@account.connection.execution_status}
        />
      </div>

      <p class="font-medium truncate">{account_name(@account)}</p>
      <p class="text-xs opacity-50 truncate">{account_details(@account)}</p>

      <%= if Account.credit_card?(@account) do %>
        <div class="mt-3">
          <p class="text-xs opacity-60">Fatura atual</p>
          <p class="text-xl font-semibold tabular-nums">
            {format_money(@account.balance, @account.currency_code)}
          </p>
          <div :if={@account.credit_limit} class="mt-2">
            <progress
              class="progress progress-warning w-full h-1.5"
              value={limit_usage(@account)}
              max="100"
            >
            </progress>
            <p class="text-xs opacity-60 mt-1">
              Limite {format_money(@account.credit_limit, @account.currency_code)} · disponível {format_money(
                @account.available_credit_limit,
                @account.currency_code
              )}
            </p>
          </div>
          <p :if={@account.balance_due_date} class="text-xs opacity-60 mt-1">
            Fecha {format_date(@account.balance_close_date)} · vence {format_date(
              @account.balance_due_date
            )}
          </p>
        </div>
      <% else %>
        <div class="mt-3">
          <p class="text-xs opacity-60">Saldo</p>
          <p class="text-xl font-semibold tabular-nums">
            {format_money(@account.balance, @account.currency_code)}
          </p>
          <p
            :if={
              @account.automatically_invested_balance &&
                Decimal.positive?(@account.automatically_invested_balance)
            }
            class="text-xs opacity-60 mt-1"
          >
            + {format_money(@account.automatically_invested_balance, @account.currency_code)} aplicado automaticamente
          </p>
        </div>
      <% end %>

      <p class="text-[11px] opacity-40 mt-3">
        Sincronizado {time_ago(@account.synced_at)}
      </p>
    </.link>
    """
  end

  defp account_kind(%Account{subtype: "CREDIT_CARD"}), do: "Cartão de crédito"
  defp account_kind(%Account{subtype: "SAVINGS_ACCOUNT"}), do: "Poupança"
  defp account_kind(%Account{}), do: "Conta corrente"

  defp account_details(%Account{type: "CREDIT"} = account) do
    [account.brand, account.level, account.number && "final #{account.number}"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp account_details(account) do
    [account.transfer_number || account.number, account.owner]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp limit_usage(%Account{credit_limit: limit, balance: balance}) do
    if Decimal.positive?(limit) and balance do
      balance
      |> Decimal.div(limit)
      |> Decimal.mult(100)
      |> Decimal.to_float()
      |> max(0.0)
      |> min(100.0)
    else
      0
    end
  end

  # A direção vem de `type` (DEBIT = saída); o sinal de `amount` muda de convenção entre conta e cartão.
  defp signed_amount(transaction) do
    prefix = if transaction.type == "CREDIT", do: "+ ", else: "- "
    prefix <> format_money(Decimal.abs(transaction.amount), transaction.currency_code)
  end

  @doc """
  Símbolo oficial do Open Finance Brasil (manual de identidade da marca). O arco
  usa a cor do texto, como nas versões positiva e negativa, para funcionar nos
  temas claro e escuro.
  """
  attr :class, :string, default: "size-5"

  def open_finance_logo(assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="207 210 380 380"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Open Finance Brasil"
    >
      <path
        fill="currentColor"
        d="M548.28,343.77c-14.25-24.74-34.07-44.33-59.47-58.76c-22.36-12.7-46.06-19.81-71.09-21.33v72.33c20.36,1.81,37.39,9.88,51.09,24.21c15.67,16.4,23.52,37.72,23.52,63.96c0,26.25-7.98,47.7-23.94,64.38c-15.96,16.69-35.96,25.02-59.99,25.02c-21.98,0-40.46-6.92-55.45-20.72l-51.31,51.31C331.4,571.39,366.75,585,407.7,585c29.81,0,57.08-7.07,81.82-21.22c24.98-14.29,44.67-34.17,59.04-59.65c13.58-24.06,20.88-51.39,21.07-79.02C569.84,395.98,562.72,368.86,548.28,343.77z"
      />
      <path
        fill="#4A7E94"
        d="M351.76,357.87c13.24-12.74,29.12-20.01,47.63-21.8V215c-47.21,3.46-92.04,26.16-123.48,67.03L351.76,357.87zM325.57,416.8c1.06-17.12,5.84-32.07,14.36-44.83l-77.08-77.08c-26.69,37.27-36.3,84.78-31.18,121.9H325.57zM325.81,435.13h-94.13c7.19,42.85,31.23,74.79,57.09,95.99l52.08-52.08C332.3,466.69,327.3,452.05,325.81,435.13z"
      />
    </svg>
    """
  end

  @doc "Badge com o status do Item na Pluggy."
  attr :status, :string, required: true
  attr :execution_status, :string, default: nil

  def status_badge(assigns) do
    {label, class} = status_info(assigns.status, assigns.execution_status)
    assigns = assign(assigns, label: label, class: class)

    ~H"""
    <span class={["badge badge-sm whitespace-nowrap", @class]}>{@label}</span>
    """
  end

  defp status_info("UPDATED", "PARTIAL_SUCCESS"), do: {"Atualizado em parte", "badge-warning"}
  defp status_info("UPDATED", _), do: {"Atualizado", "badge-success badge-soft"}
  defp status_info("UPDATING", _), do: {"Atualizando", "badge-info badge-soft"}
  defp status_info("LOGIN_ERROR", _), do: {"Reautorizar", "badge-error"}
  defp status_info("OUTDATED", _), do: {"Desatualizado", "badge-warning"}
  defp status_info("WAITING_USER_INPUT", _), do: {"Aguardando você", "badge-warning"}
  defp status_info(status, _), do: {status || "—", "badge-ghost"}

  defp sync_label(true, _last_synced_at), do: "Sincronizando..."
  defp sync_label(false, nil), do: "Aguardando a primeira sincronização"
  defp sync_label(false, last_synced_at), do: "Sincronizado #{time_ago(last_synced_at)}"

  defp accounts_summary([]), do: "Nenhuma conta sincronizada ainda"

  defp accounts_summary(accounts) do
    Enum.map_join(accounts, " · ", &account_name/1)
  end

  @doc "Nome de exibição da conta."
  def account_name(account), do: account.marketing_name || account.name || "Conta"

  @doc "Tempo relativo em português (\"há 5 min\")."
  def time_ago(%DateTime{} = datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime)

    cond do
      seconds < 60 -> "agora há pouco"
      seconds < 3_600 -> "há #{div(seconds, 60)} min"
      seconds < 86_400 -> "há #{div(seconds, 3_600)} h"
      seconds < 172_800 -> "ontem"
      true -> "há #{div(seconds, 86_400)} dias"
    end
  end

  @doc "Formata valores monetários (`R$ 1.234,56`; outras moedas com o código)."
  def format_money(amount, currency \\ "BRL")
  def format_money(nil, _currency), do: "—"

  def format_money(%Decimal{} = amount, currency) do
    sign = if Decimal.negative?(amount), do: "-", else: ""
    symbol = if currency in [nil, "BRL"], do: "R$", else: currency
    "#{sign}#{symbol} #{br_number(amount)}"
  end

  defp br_number(amount) do
    [int_part, dec_part] =
      amount
      |> Decimal.abs()
      |> Decimal.round(2)
      |> Decimal.to_string(:normal)
      |> String.split(".")
      |> case do
        [int_part] -> [int_part, "00"]
        parts -> parts
      end

    int_part =
      int_part
      |> String.reverse()
      |> String.to_charlist()
      |> Enum.chunk_every(3)
      |> Enum.join(".")
      |> String.reverse()

    "#{int_part},#{String.pad_trailing(dec_part, 2, "0")}"
  end

  @doc "Data no formato brasileiro (dd/mm/aaaa)."
  def format_date(nil), do: "—"
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%d/%m/%Y")
end
