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
        Open Finance Brasil. As faturas e extratos que você importa continuam valendo; o Open
        Finance só preenche os meses ainda sem upload.
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
          conecte de novo. Os dados são atualizados sozinhos (no máximo uma vez por hora) e
          aparecem no Resumo do Dashboard.
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
  Bloco "Hoje" do Resumo: o estado atual pelo Open Finance. Totais e alertas no
  topo; contas e cartões agrupados por banco; num bloco recolhível, um calendário
  em miniatura (o mesmo da aba de uploads) mostra os meses em que o Open Finance
  supre a falta de upload. Não obedece aos filtros de período do histórico.
  """
  attr :accounts, :list, required: true, doc: "contas com a conexão pré-carregada"
  attr :totals, :map, required: true
  attr :calendar, :list, required: true, doc: "linhas de `OpenFinance.coverage_calendar/1`"
  attr :refreshed_at, :any, required: true

  def today(assigns) do
    of_months =
      for row <- assigns.calendar, cell <- row.cells, cell.open_finance != [], do: cell

    assigns =
      assign(assigns,
        groups: Enum.chunk_by(assigns.accounts, & &1.connection_id),
        alerts: alerts(assigns.accounts),
        of_month_count: length(of_months)
      )

    ~H"""
    <section
      id="open-finance-today"
      class="card bg-base-200 border border-base-content/5 p-4 sm:p-5 mb-6"
    >
      <div class="flex flex-wrap items-center gap-x-2 gap-y-1 mb-4">
        <h2 class="text-sm font-semibold uppercase tracking-wide">Hoje</h2>
        <span class="text-xs opacity-50 flex items-center gap-1">
          <.open_finance_logo class="size-3.5" /> Open Finance
          <span :if={@refreshed_at}>· atualizado {time_ago(@refreshed_at)}</span>
        </span>
      </div>

      <div id="open-finance-today-totals" class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-4">
        <div>
          <p class="text-xs opacity-60">Em conta</p>
          <p class="text-xl font-semibold tabular-nums">{format_money(@totals.bank)}</p>
          <p class="text-[11px] opacity-50">saldo somado de {@totals.bank_count} conta(s)</p>
        </div>
        <div>
          <p class="text-xs opacity-60">Faturas abertas</p>
          <p class="text-xl font-semibold tabular-nums text-warning">
            {format_money(@totals.card_used)}
          </p>
          <p class="text-[11px] opacity-50">somando {@totals.card_count} cartão(ões)</p>
        </div>
        <div>
          <p class="text-xs opacity-60">Limite disponível</p>
          <p class="text-xl font-semibold tabular-nums text-success">
            {format_money(@totals.card_available)}
          </p>
          <p class="text-[11px] opacity-50">de {format_money(@totals.card_limit)} de limite total</p>
        </div>
      </div>

      <ul :if={@alerts != []} id="open-finance-today-alerts" class="mb-4 space-y-1 text-xs">
        <li :for={alert <- @alerts} class="flex items-start gap-1.5 text-warning">
          <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" /> {alert}
        </li>
      </ul>

      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        <.bank_group :for={accounts <- @groups} accounts={accounts} />
      </div>

      <details :if={@of_month_count > 0} id="open-finance-today-sources" class="group mt-4">
        <summary class="flex items-center gap-1.5 text-xs opacity-60 cursor-pointer select-none list-none hover:opacity-90 transition-opacity">
          <.icon
            name="hero-chevron-right"
            class="size-3.5 transition-transform group-open:rotate-90"
          /> Meses sem upload cobertos pelo Open Finance ({@of_month_count})
        </summary>
        <div class="mt-3 ml-5 flex flex-col md:flex-row md:items-end gap-4">
          <.mini_calendar rows={@calendar} />
          <div class="flex flex-col gap-2 text-[11px] opacity-80">
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
            <.link
              id="open-finance-calendar-link"
              navigate={~p"/upload?tab=calendario"}
              class="btn btn-ghost btn-xs gap-1 self-start group/link"
            >
              <.icon name="hero-calendar-days" class="size-3.5" /> Ver calendário completo
              <.icon
                name="hero-arrow-right"
                class="size-3 transition-transform group-hover/link:translate-x-0.5"
              />
            </.link>
          </div>
        </div>
      </details>
    </section>
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
        <div :for={m <- 1..12} class="w-[18px] text-center text-[9px] opacity-50">
          {month_initial(m)}
        </div>
      </div>
      <div :for={row <- @rows} class="flex gap-1 items-center mb-1">
        <div class="w-8 shrink-0 text-right pr-1 text-[10px] opacity-60 tabular-nums">
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

  defp mini_cell_class(%{future?: true}), do: "calendar-count-future opacity-60"
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

    assigns = assign(assigns, connection: connection, cards: cards, banks: banks)

    ~H"""
    <div id={"today-bank-#{@connection.id}"} class="rounded-xl bg-base-100/60 p-3">
      <div class="flex items-center gap-2 mb-2">
        <img src={bank_logo(@connection.bank)} alt="" class="size-6 rounded-full shrink-0" />
        <span class="font-medium">{bank_name(@connection.bank)}</span>
        <span :if={@connection.holder_type == "PJ"} class="badge badge-ghost badge-xs">PJ</span>
      </div>

      <div :if={@banks != []} class="mb-2">
        <p class="text-[10px] font-semibold uppercase tracking-wide opacity-40 mb-1">Contas</p>
        <div
          :for={account <- @banks}
          id={"today-account-#{account.id}"}
          class={[
            "flex items-baseline justify-between gap-2 py-0.5 text-sm",
            zero?(account.balance) && "opacity-40"
          ]}
        >
          <span class="truncate">
            {account_kind(account)}<span :if={account.number} class="opacity-50"> ••{last4(account.number)}</span>
          </span>
          <span class={[
            "font-medium tabular-nums whitespace-nowrap",
            account.balance && Decimal.negative?(account.balance) && "text-error"
          ]}>
            {format_money(account.balance, account.currency_code)}
          </span>
        </div>
      </div>

      <div :if={@cards != []}>
        <p class="text-[10px] font-semibold uppercase tracking-wide opacity-40 mb-1">
          Cartão de crédito
        </p>
        <div :for={card <- @cards} id={"today-card-#{card.id}"} class="py-0.5 mb-1.5 last:mb-0">
          <div class="flex items-baseline justify-between gap-2 text-sm">
            <span class="truncate">
              {card_name(card)}<span :if={card.number} class="opacity-50"> ••{last4(card.number)}</span>
            </span>
            <span class="text-right whitespace-nowrap">
              <span class="block text-[10px] opacity-50 leading-none">fatura atual</span>
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
            <p class="text-[11px] opacity-60 mt-0.5">
              {round(limit_usage(card))}% do limite usado · disponível {format_money(
                card.available_credit_limit,
                card.currency_code
              )} de {format_money(card.credit_limit, card.currency_code)}
            </p>
          </div>
          <p :if={card.balance_due_date} class="text-[11px] opacity-60">
            {due_dates(card)}
          </p>
        </div>
      </div>
    </div>
    """
  end

  # Só o que pede ação: fatura com valor a pagar vencendo em até 5 dias, saldo negativo.
  defp alerts(accounts) do
    today = Date.utc_today()

    Enum.flat_map(accounts, fn account ->
      cond do
        (Account.credit_card?(account) and positive?(account.balance) and
           account.balance_due_date) &&
            Date.diff(account.balance_due_date, today) in 0..5 ->
          days = Date.diff(account.balance_due_date, today)
          when_text = if days == 0, do: "vence hoje", else: "vence em #{days} dia(s)"

          [
            "Fatura #{bank_name(account.connection.bank)} #{card_name(account)} #{when_text}: #{format_money(account.balance)}"
          ]

        (not Account.credit_card?(account) and account.balance) &&
            Decimal.negative?(account.balance) ->
          ["Saldo negativo: #{bank_name(account.connection.bank)} #{account_kind(account)}"]

        true ->
          []
      end
    end)
  end

  # Uso real do limite: o que já está comprometido (fatura aberta, fechada a pagar,
  # parcelas futuras), e não só a fatura atual.
  defp limit_usage(%Account{
         credit_limit: limit,
         available_credit_limit: available,
         balance: balance
       }) do
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

  defp positive?(%Decimal{} = value), do: Decimal.positive?(value)
  defp positive?(_value), do: false

  defp zero?(%Decimal{} = value), do: Decimal.equal?(value, 0)
  defp zero?(_value), do: true

  defp account_kind(%Account{subtype: "SAVINGS_ACCOUNT"}), do: "Poupança"
  defp account_kind(%Account{}), do: "Conta corrente"

  # "VISA INFINITE PRIME" → "Visa Infinite Prime"; "platinum" → "Platinum".
  defp card_name(%Account{} = card) do
    (card.marketing_name || card.name || "Cartão")
    |> String.downcase()
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

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

  defp sync_label(true, _last_synced_at), do: "Importando contas e transações..."
  defp sync_label(false, nil), do: "Aguardando a primeira leitura"
  defp sync_label(false, last_synced_at), do: "Atualizado #{time_ago(last_synced_at)}"

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
