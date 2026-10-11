defmodule GranaWeb.OpenFinanceComponents do
  @moduledoc """
  Componentes da integração Open Finance (Pluggy): o card de Configurações e o
  bloco "Hoje" do Resumo.
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
    <.card
      id="open-finance-settings"
      title="Open Finance"
      description="Saldos, cartões e transações lidos direto dos seus bancos, com o consentimento do Open Finance Brasil. As faturas e extratos que você importa continuam valendo; o Open Finance só preenche os meses ainda sem upload."
    >
      <:logo><.open_finance_logo class="size-5 shrink-0" /></:logo>
      <:title_extra>
        <.tag kind="neutro">
          via <img src={~p"/images/pluggy-logo.png"} alt="Pluggy" class="h-3 w-auto" />
        </.tag>
      </:title_extra>

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

        <div>
          <.empty_state
            :if={@connections == []}
            id="open-finance-empty"
            icon="hero-building-library"
            title="Nenhum banco conectado ainda"
            text="Conecte pelo Meu Pluggy abaixo. Cada banco autorizado lá vira uma conexão aqui."
          />
          <ul
            :if={@connections != []}
            id="open-finance-connections"
            class="divide-y divide-base-content/10"
          >
            <.connection_row
              :for={connection <- @connections}
              connection={connection}
              syncing={MapSet.member?(@syncing, connection.id)}
            />
          </ul>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <.button
            id="connect-meu-pluggy"
            type="button"
            variant="primary"
            size="sm"
            icon={if !@connecting, do: "hero-plus"}
            disabled={@connecting}
            phx-click="open_finance_connect"
          >
            <span :if={@connecting} class="loading loading-spinner loading-xs"></span>
            {if @connecting, do: "Abrindo widget…", else: "Conectar via Meu Pluggy"}
          </.button>
          <.button
            id="toggle-item-form"
            type="button"
            variant="ghost"
            size="sm"
            phx-click="open_finance_toggle_item_form"
          >
            Tenho o itemId
          </.button>
        </div>

        <.form
          :if={@show_item_form}
          for={@item_form}
          id="open-finance-item-form"
          phx-submit="open_finance_add_item"
        >
          <div class="flex flex-col sm:flex-row gap-2 sm:items-start">
            <div class="flex-1 min-w-0 sm:max-w-sm">
              <.input
                field={@item_form[:item_id]}
                type="text"
                placeholder="itemId (UUID)"
                class="input w-full font-mono"
                autocomplete="off"
                spellcheck="false"
              />
            </div>
            <div class="flex gap-2">
              <.button variant="primary" class="flex-1 sm:flex-none" loading="Verificando…">
                Adicionar
              </.button>
              <.button
                id="cancel-item-form"
                type="button"
                variant="ghost"
                phx-click="open_finance_toggle_item_form"
              >
                Cancelar
              </.button>
            </div>
          </div>
          <p class="ui-help">
            No dashboard da Pluggy: Aplicações → sua aplicação → Demo → Itens Conectados.
          </p>
        </.form>

        <p class="ui-help leading-relaxed">
          No widget, entre com a sua conta do Meu Pluggy e escolha um banco. Para outro banco,
          conecte de novo. Os dados são atualizados sozinhos (no máximo uma vez por hora) e
          aparecem no Resumo do Painel.
        </p>
      <% end %>
    </.card>
    """
  end

  attr :source, :atom, required: true
  attr :client_id, :string, default: nil
  attr :form, :any, required: true
  attr :show_form, :boolean, required: true
  attr :private_key, :boolean, required: true

  defp credentials(assigns) do
    ~H"""
    <div id="open-finance-credentials" class="flex flex-col gap-6">
      <%= case @source do %>
        <% :database -> %>
          <ul class="divide-y divide-base-content/10">
            <.item_row
              id="credentials-saved"
              title="Credenciais da Pluggy"
              subtitle={"Client ID #{@client_id}"}
            >
              <:leading><.icon name="hero-key" class="size-5 shrink-0" /></:leading>
              <:tags>
                <.tag kind="salvo" />
                <.tag kind="criptografado" />
              </:tags>
              <:actions>
                <.button
                  id="replace-credentials"
                  type="button"
                  variant="ghost"
                  size="sm"
                  phx-click="open_finance_toggle_credentials_form"
                >
                  Substituir
                </.button>
                <.button
                  id="remove-credentials"
                  type="button"
                  variant="ghost"
                  size="sm"
                  class="text-error"
                  phx-click={show_modal("remove-credentials-modal")}
                >
                  Remover
                </.button>
              </:actions>
            </.item_row>
          </ul>
          <.confirm_modal
            id="remove-credentials-modal"
            title="Apagar as credenciais da Pluggy?"
            confirm="Apagar credenciais"
            loading="Apagando…"
            on_confirm={JS.push("open_finance_remove_credentials")}
          >
            As conexões ficam, mas param de sincronizar até você informar credenciais de novo.
          </.confirm_modal>
        <% :env -> %>
          <div id="credentials-env">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-3">
              <.env_field id="credentials-env-client-id" label="Client ID" var="PLUGGY_CLIENT_ID" />
              <.env_field
                id="credentials-env-client-secret"
                label="Client Secret"
                secret
                var="PLUGGY_CLIENT_SECRET"
              />
            </div>
          </div>
        <% nil -> %>
          <.setup_steps />
      <% end %>

      <.notice
        :if={(is_nil(@source) or (@source == :database and @show_form)) and !@private_key}
        id="cloak-key-warning"
        tone={:warning}
        title="Defina uma CLOAK_KEY antes"
      >
        Sem ela o Grana criptografa com a chave de desenvolvimento, que é pública no repositório. Gere
        com <code>openssl rand -base64 32</code>, coloque <code>CLOAK_KEY=...</code>
        no <code>.env</code>
        e reinicie o servidor.
      </.notice>

      <.form
        :if={(is_nil(@source) or (@source == :database and @show_form)) and @private_key}
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
        <div class="sm:col-span-2 mt-2 flex flex-col gap-3 sm:flex-row sm:items-center">
          <.button
            variant="primary"
            size="sm"
            class="w-full sm:w-auto"
            loading="Verificando na Pluggy…"
          >
            Salvar e verificar
          </.button>
          <p class="ui-help">
            Conferido na Pluggy e guardado criptografado. O secret nunca volta para esta tela.
          </p>
        </div>
      </.form>
    </div>
    """
  end

  attr :connection, :map, required: true
  attr :syncing, :boolean, required: true

  defp connection_row(assigns) do
    ~H"""
    <.item_row
      id={"connection-#{@connection.id}"}
      title={@connection.connector_name || "Conexão"}
      subtitle={accounts_summary(@connection.accounts)}
    >
      <:leading>
        <img
          :if={@connection.connector_image_url}
          src={@connection.connector_image_url}
          alt=""
          class="ui-rounded-field size-9 shrink-0 bg-base-100 object-contain p-1"
        />
        <div
          :if={!@connection.connector_image_url}
          class="ui-rounded-field grid size-9 shrink-0 place-items-center bg-base-100"
        >
          <.icon name="hero-building-library" class="size-5" />
        </div>
      </:leading>
      <:tags>
        <.tag :if={@syncing} kind="pendente">Importando…</.tag>
        <.status_badge
          :if={!@syncing}
          status={@connection.status}
          execution_status={@connection.execution_status}
        />
      </:tags>
      <:actions>
        <.button
          id={"remove-connection-#{@connection.id}"}
          type="button"
          variant="ghost"
          size="sm"
          icon="hero-trash"
          class="btn-square text-error"
          title="Remover conexão"
          phx-click={show_modal("remove-connection-modal-#{@connection.id}")}
        >
          <span class="sr-only">Remover conexão</span>
        </.button>
      </:actions>
      <.notice :if={@connection.sync_error} tone={:error}>{@connection.sync_error}</.notice>
      <p :if={!@connection.sync_error and !@syncing} class="ui-caption">
        {sync_label(@connection.last_synced_at)}
      </p>
      <.confirm_modal
        id={"remove-connection-modal-#{@connection.id}"}
        title="Remover esta conexão?"
        confirm="Remover conexão"
        loading="Removendo…"
        on_confirm={JS.push("open_finance_remove", value: %{id: to_string(@connection.id)})}
      >
        O acesso do Grana a ela é revogado na Pluggy e os dados importados dela são apagados. Sua
        conexão no Meu Pluggy continua intacta.
      </.confirm_modal>
    </.item_row>
    """
  end

  defp setup_steps(assigns) do
    ~H"""
    <div id="open-finance-setup">
      <p class="ui-body mb-3">Para ativar (uso pessoal, gratuito, até 5 conexões):</p>
      <ol class="ui-body ui-text-secondary ml-5 list-decimal space-y-2">
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
  Bloco "Hoje" do Resumo: o estado atual pelo Open Finance. Totais no topo;
  contas e cartões agrupados por banco, cada grupo com os seus alertas no pé; num
  bloco recolhível, um calendário em miniatura (o mesmo da aba de uploads) mostra
  os meses em que o Open Finance supre a falta de upload. Não obedece aos filtros
  de período do histórico.
  """
  attr :accounts, :list, required: true, doc: "contas com a conexão pré-carregada"
  attr :totals, :map, required: true
  attr :calendar, :list, required: true, doc: "linhas de `OpenFinance.coverage_calendar/1`"
  attr :collected_at, :any, required: true, doc: "última coleta da Pluggy nos bancos"

  def today(assigns) do
    of_months =
      for row <- assigns.calendar, cell <- row.cells, cell.open_finance != [], do: cell

    assigns =
      assign(assigns,
        groups: Enum.chunk_by(assigns.accounts, & &1.connection_id),
        of_month_count: length(of_months)
      )

    ~H"""
    <.card id="open-finance-today" title="Hoje" spaced={false} class="mb-6">
      <:logo><.open_finance_logo class="size-5 shrink-0" /></:logo>
      <:aside>
        <span class="ui-help flex flex-wrap items-center justify-end gap-x-1">
          Open Finance
          <span
            :if={@collected_at}
            id="open-finance-today-collected-at"
            title={"Última coleta da Pluggy nos bancos: #{format_brt(@collected_at)}"}
          >
            · atualizado {time_ago(@collected_at)}
          </span>
        </span>
      </:aside>

      <div id="open-finance-today-totals" class="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <.stat_tile
          id="today-total-bank"
          label="Em conta"
          value={format_money(@totals.bank)}
          caption={"saldo somado de #{@totals.bank_count} conta(s)"}
        />
        <.stat_tile
          id="today-total-card-used"
          label="Faturas abertas"
          value={format_money(@totals.card_used)}
          tone={:despesa}
          caption={"somando #{@totals.card_count} cartão(ões)"}
        />
        <.stat_tile
          id="today-total-card-available"
          label="Limite disponível"
          value={format_money(@totals.card_available)}
          tone={:receita}
          caption={"de #{format_money(@totals.card_limit)} de limite total"}
        />
      </div>

      <div class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
        <.bank_group :for={accounts <- @groups} accounts={accounts} />
      </div>

      <details :if={@of_month_count > 0} id="open-finance-today-sources" class="group">
        <summary class="ui-help flex cursor-pointer select-none list-none items-center gap-1.5 transition-colors hover:text-base-content">
          <.icon
            name="hero-chevron-right"
            class="size-3.5 transition-transform group-open:rotate-90"
          /> Meses sem upload cobertos pelo Open Finance ({@of_month_count})
        </summary>
        <div class="mt-3 ml-5 flex flex-col md:flex-row md:items-end gap-4">
          <.mini_calendar rows={@calendar} />
          <div class="ui-caption flex flex-col gap-2">
            <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
              <span class="flex items-center gap-1">
                <span class="grana-calendar-legend-swatch calendar-count-0 !size-3"></span> sem upload
              </span>
              <span class="flex items-center gap-1">
                <span class="grana-calendar-legend-swatch calendar-count-1 !size-3"></span>
                extrato ou fatura
              </span>
              <span class="flex items-center gap-1">
                <span class="grana-calendar-legend-swatch calendar-count-3 !size-3"></span>
                extrato e fatura
              </span>
              <span class="flex items-center gap-1">
                <span class="grid place-items-center size-3 rounded-full bg-base-100 shadow-sm">
                  <.open_finance_logo class="size-2" />
                </span>
                veio do Open Finance
              </span>
            </div>
            <.button
              id="open-finance-calendar-link"
              navigate={~p"/upload?tab=calendario"}
              variant="ghost"
              size="sm"
              icon="hero-calendar-days"
              class="self-start"
            >
              Ver calendário completo
            </.button>
          </div>
        </div>
      </details>
    </.card>
    """
  end

  attr :rows, :list, required: true

  # Miniatura do calendário da aba de uploads: mesmas cores (tipos importados no
  # mês) e o símbolo do Open Finance nos meses que tiveram dados vindos dele.
  defp mini_calendar(assigns) do
    ~H"""
    <div id="open-finance-mini-calendar" class="inline-block">
      <div class="flex gap-1 mb-1">
        <div class="w-8 shrink-0"></div>
        <div :for={m <- 1..12} class="ui-caption w-[18px] text-center">
          {month_initial(m)}
        </div>
      </div>
      <div :for={row <- @rows} class="flex gap-1 items-center mb-1">
        <div class="ui-caption w-8 shrink-0 pr-1 text-right tabular-nums">
          {row.year}
        </div>
        <div
          :for={cell <- row.cells}
          id={"mini-calendar-#{cell.year}-#{cell.month}"}
          class={[
            "grana-calendar-cell size-[18px] grid place-items-center",
            mini_cell_class(cell)
          ]}
          title={mini_cell_title(cell)}
        >
          <span
            :if={cell.open_finance != []}
            class="grid place-items-center size-3 rounded-full bg-base-100 shadow-sm"
          >
            <.open_finance_logo class="size-2" />
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp mini_cell_class(%{future?: true}), do: "calendar-count-future"
  defp mini_cell_class(%{upload_types: []}), do: "calendar-count-0"
  defp mini_cell_class(%{upload_types: [_]}), do: "calendar-count-1"
  defp mini_cell_class(%{upload_types: _both}), do: "calendar-count-3"

  defp mini_cell_title(%{future?: true}), do: nil

  defp mini_cell_title(cell) do
    uploads =
      case cell.upload_types do
        [] -> "sem upload"
        types -> "upload: " <> Enum.join(types, " e ")
      end

    open_finance =
      Enum.map_join(cell.open_finance, ", ", fn {bank, type} -> "#{bank_name(bank)} (#{type})" end)

    label = "#{month_abbr(cell.month)}/#{cell.year} · #{uploads}"
    if open_finance == "", do: label, else: "#{label} · Open Finance: #{open_finance}"
  end

  @month_abbr {"Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"}
  defp month_abbr(month), do: elem(@month_abbr, month - 1)
  defp month_initial(month), do: month |> month_abbr() |> String.first()

  attr :accounts, :list, required: true

  defp bank_group(assigns) do
    connection = hd(assigns.accounts).connection
    {cards, banks} = Enum.split_with(assigns.accounts, &Account.credit_card?/1)

    assigns =
      assign(assigns,
        connection: connection,
        cards: cards,
        banks: banks,
        alerts: Grana.OpenFinance.Alerts.list(assigns.accounts)
      )

    ~H"""
    <div id={"today-bank-#{@connection.id}"} class="ui-rounded-box flex flex-col bg-base-100/60 p-3">
      <div class="flex items-center gap-2 mb-2">
        <img src={bank_logo(@connection.bank)} alt="" class="size-6 rounded-full shrink-0" />
        <span class="font-medium">{bank_name(@connection.bank)}</span>
        <.tag :if={@connection.holder_type == "PJ"} kind="neutro">PJ</.tag>
      </div>

      <div :if={@banks != []} class="mb-2">
        <p class="ui-caption mb-1 font-semibold uppercase tracking-wide">Contas</p>
        <div
          :for={account <- @banks}
          id={"today-account-#{account.id}"}
          class={[
            "flex items-baseline justify-between gap-2 py-0.5 text-sm",
            zero?(account.balance) && "ui-text-tertiary"
          ]}
        >
          <span class="truncate">
            {account_kind(account)}<span :if={account.number} class="ui-text-tertiary"> ••{last4(account.number)}</span>
          </span>
          <span class={[
            "font-medium tabular-nums whitespace-nowrap",
            account.balance && Decimal.negative?(account.balance) && "ui-money-despesa"
          ]}>
            {format_money(account.balance, account.currency_code)}
          </span>
        </div>
      </div>

      <div :if={@cards != []}>
        <p class="ui-caption mb-1 font-semibold uppercase tracking-wide">
          Cartão de crédito
        </p>
        <div :for={card <- @cards} id={"today-card-#{card.id}"} class="py-0.5 mb-1.5 last:mb-0">
          <div class="flex items-baseline justify-between gap-2 text-sm">
            <span class="truncate">
              {card_name(card)}<span :if={card.number} class="ui-text-tertiary"> ••{last4(card.number)}</span>
            </span>
            <span class="text-right whitespace-nowrap">
              <span class="ui-caption block leading-none">fatura atual</span>
              <span class="font-medium tabular-nums">
                {format_money(card.balance, card.currency_code)}
              </span>
            </span>
          </div>
          <div :if={positive?(card.credit_limit)} class="mt-1">
            <progress
              class="progress progress-warning w-full h-1"
              value={limit_usage(card)}
              max="100"
            >
            </progress>
            <p class="ui-caption mt-0.5">
              {round(limit_usage(card))}% do limite usado · disponível {format_money(
                card.available_credit_limit,
                card.currency_code
              )} de {format_money(Account.effective_credit_limit(card), card.currency_code)}
            </p>
            <p
              :if={custom_limit?(card)}
              id={"today-card-#{card.id}-custom-limit"}
              class="ui-caption"
            >
              limite ajustado por você no app · aprovado {format_money(
                card.credit_limit,
                card.currency_code
              )}
            </p>
          </div>
          <p :if={card.balance_due_date} class="ui-caption">
            {due_dates(card)}
          </p>
        </div>
      </div>

      <ul
        :if={@alerts != []}
        id={"today-alerts-#{@connection.id}"}
        class="mt-auto pt-2 border-t border-base-content/5 space-y-1 text-xs"
      >
        <li :for={alert <- @alerts} class="flex items-start gap-1.5 text-warning">
          <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" /> {alert.message}
        </li>
      </ul>
    </div>
    """
  end

  # Uso real do limite: o que já está comprometido (fatura aberta, fechada a pagar,
  # parcelas futuras), e não só a fatura atual — medido sobre o teto efetivo, já
  # que o disponível do banco desconta o limite que o cliente reduziu no app.
  defp limit_usage(%Account{available_credit_limit: available, balance: balance} = card) do
    limit = Account.effective_credit_limit(card)
    used = if available, do: Decimal.sub(limit, available), else: balance

    if used do
      used
      |> Decimal.div(limit)
      |> Decimal.mult(100)
      |> Decimal.to_float()
      |> max(0.0)
      |> min(100.0)
    else
      0.0
    end
  end

  defp custom_limit?(card), do: Account.effective_credit_limit(card) != card.credit_limit

  defp positive?(%Decimal{} = value), do: Decimal.positive?(value)
  defp positive?(_value), do: false

  defp zero?(%Decimal{} = value), do: Decimal.equal?(value, 0)
  defp zero?(_value), do: true

  defp account_kind(account), do: Account.kind_label(account)
  defp card_name(card), do: Account.card_name(card)

  defp last4(number), do: String.slice(number, -4, 4)

  defp due_dates(%Account{balance_close_date: nil} = card),
    do: "vence #{format_short_date(card.balance_due_date)}"

  defp due_dates(card),
    do:
      "fecha #{format_short_date(card.balance_close_date)} · vence #{format_short_date(card.balance_due_date)}"

  defp bank_logo("nubank"), do: ~p"/images/nubank-logo.png"
  defp bank_logo("bradesco"), do: ~p"/images/bradesco-logo.png"
  defp bank_logo(_), do: ~p"/images/logo-32.png"

  defp bank_name("nubank"), do: "Nubank"
  defp bank_name("bradesco"), do: "Bradesco"
  defp bank_name(bank), do: String.capitalize(bank || "")

  defp format_short_date(%Date{} = date), do: Calendar.strftime(date, "%d/%m")

  defp format_brt(%DateTime{} = datetime) do
    datetime |> DateTime.add(-3, :hour) |> Calendar.strftime("%d/%m às %H:%M")
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

  @doc "Tag com o status do Item na Pluggy."
  attr :status, :string, required: true
  attr :execution_status, :string, default: nil

  def status_badge(assigns) do
    {label, kind} = status_info(assigns.status, assigns.execution_status)
    assigns = assign(assigns, label: label, kind: kind)

    ~H"""
    <.tag kind={@kind}>{@label}</.tag>
    """
  end

  defp status_info("UPDATED", "PARTIAL_SUCCESS"), do: {"Atualizado em parte", "pendente"}
  defp status_info("UPDATED", _), do: {"Atualizado", "ativo"}
  defp status_info("UPDATING", _), do: {"Atualizando", "pendente"}
  defp status_info("LOGIN_ERROR", _), do: {"Reautorizar", "erro"}
  defp status_info("OUTDATED", _), do: {"Desatualizado", "pendente"}
  defp status_info("WAITING_USER_INPUT", _), do: {"Aguardando você", "pendente"}
  defp status_info(status, _), do: {status || "—", "neutro"}

  defp sync_label(nil), do: "Aguardando a primeira leitura"
  defp sync_label(last_synced_at), do: "Atualizado #{time_ago(last_synced_at)}"

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
      seconds < 60 -> "há instantes"
      seconds < 3_600 -> "há #{div(seconds, 60)} min"
      seconds < 86_400 -> "há #{div(seconds, 3_600)} h"
      seconds < 172_800 -> "ontem"
      true -> "há #{div(seconds, 86_400)} dias"
    end
  end

  @doc "Formata valores monetários (`R$ 1.234,56`; outras moedas com o código)."
  def format_money(amount, currency \\ "BRL"), do: Grana.Money.format(amount, currency)

  @doc "Data no formato brasileiro (dd/mm/aaaa)."
  def format_date(nil), do: "—"
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%d/%m/%Y")
end
