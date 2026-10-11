defmodule GranaWeb.DashboardLive do
  use GranaWeb, :live_view

  alias Grana.Banking
  alias Grana.Banking.FinancialGoal
  alias Grana.OpenFinance
  alias GranaWeb.OpenFinanceComponents

  # ── Mount ──

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    Banking.ensure_default_categories(user_id)

    # Recategoriza impostos/taxas já importados (IOF, DAS, multa…). Só conectado,
    # conservador e idempotente — após a 1ª vez não há nada a mover.
    if connected?(socket), do: Banking.reclassify_taxes(user_id)

    # Banking base data (default tab)
    available_years = Banking.available_years(user_id)
    months = Banking.available_months(user_id)
    banks = Banking.available_banks(user_id)

    {year, month, view_mode} =
      case months do
        [{y, m} | _] -> {y, m, "month"}
        [] -> {Date.utc_today().year, Date.utc_today().month, "month"}
      end

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:tab, "banking")
      # Banking state
      |> assign(:available_years, available_years)
      |> assign(:available_months, months)
      |> assign(:banks, banks)
      |> assign(:selected_year, year)
      |> assign(:selected_month, month)
      |> assign(:view_mode, view_mode)
      |> assign(:selected_bank, "all")
      |> assign(:selected_type, "all")
      |> assign(:selected_txn_type, "all")
      |> assign(:excluded_categories, MapSet.new())
      |> load_banking_data()
      # Recurring-expenses state (lazy loaded on first tab switch)
      |> assign(:rec_loaded, false)
      |> assign(:rec_window, "6")
      |> assign(:rec_bank, "all")
      |> assign(:rec_type, "all")
      |> assign_today()

    # O Open Finance é relido em segundo plano se a última leitura tiver mais de
    # 1h; quando terminar, chega {:open_finance_synced, _} e a tela se atualiza.
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Grana.PubSub, OpenFinance.topic(user_id))
      OpenFinance.refresh_if_stale(socket.assigns.current_scope)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = params["tab"] || "banking"

    socket =
      case tab do
        "recurring" ->
          socket
          |> then(fn s -> if s.assigns[:rec_loaded], do: s, else: load_recurring_data(s) end)
          |> assign(:tab, "recurring")

        _ ->
          assign(socket, :tab, "banking")
      end

    {:noreply, socket}
  end

  # ── Events: Tab Switch ──

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard?tab=#{tab}")}
  end

  # ── Events: Recurring expenses tab ──

  def handle_event("rec_set_window", %{"window" => window}, socket) do
    {:noreply, socket |> assign(:rec_window, window) |> load_recurring_data()}
  end

  def handle_event("rec_select_bank", %{"bank" => bank}, socket) do
    {:noreply, socket |> assign(:rec_bank, bank) |> load_recurring_data()}
  end

  def handle_event("rec_select_type", %{"type" => type}, socket) do
    {:noreply, socket |> assign(:rec_type, type) |> load_recurring_data()}
  end

  # ── Events: Period Selection ──

  def handle_event("select_view_total", _params, socket) do
    socket =
      socket
      |> assign(:view_mode, "total")
      |> load_banking_data()

    {:noreply, socket}
  end

  def handle_event("select_year", %{"year" => year_str}, socket) do
    year = GranaWeb.Params.to_int(year_str, Date.utc_today().year)

    socket =
      socket
      |> assign(:selected_year, year)
      |> assign(:view_mode, "year")
      |> load_banking_data()

    {:noreply, socket}
  end

  def handle_event("select_month", %{"month" => "all"}, socket) do
    socket =
      socket
      |> assign(:view_mode, "year")
      |> load_banking_data()

    {:noreply, socket}
  end

  def handle_event("select_month", %{"month" => month_str}, socket) do
    month = GranaWeb.Params.to_int(month_str, 0)

    socket =
      socket
      |> assign(:selected_month, month)
      |> assign(:view_mode, "month")
      |> load_banking_data()

    {:noreply, socket}
  end

  def handle_event("chart-navigate", %{"url" => url}, socket) do
    {:noreply, push_navigate(socket, to: url)}
  end

  # ── Events: Banking Only ──

  def handle_event("select_bank", %{"bank" => bank}, socket) do
    socket =
      socket
      |> assign(:selected_bank, bank)
      |> load_banking_data()

    {:noreply, socket}
  end

  def handle_event("select_type", %{"type" => type}, socket) do
    socket =
      socket
      |> assign(:selected_type, type)
      |> load_banking_data()

    {:noreply, socket}
  end

  def handle_event("select_txn_type", %{"txn_type" => txn_type}, socket) do
    socket =
      socket
      |> assign(:selected_txn_type, txn_type)
      |> load_banking_data()

    {:noreply, socket}
  end

  def handle_event("toggle-category", %{"id" => "nil"}, socket) do
    excluded = toggle_set(socket.assigns.excluded_categories, nil)
    {:noreply, assign(socket, :excluded_categories, excluded)}
  end

  def handle_event("toggle-category", %{"id" => id_str}, socket) do
    excluded = toggle_set(socket.assigns.excluded_categories, GranaWeb.Params.to_int(id_str, -1))
    {:noreply, assign(socket, :excluded_categories, excluded)}
  end

  def handle_event("reset-categories", _params, socket) do
    {:noreply, assign(socket, :excluded_categories, MapSet.new())}
  end

  # ── PubSub: Open Finance ──

  # Uma releitura do Open Finance pode trazer o retrato novo e transações dos
  # períodos sem upload (inclusive um mês novo nos seletores).
  @impl true
  def handle_info({:open_finance_synced, _connection_id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    socket =
      socket
      |> assign_today()
      |> assign(:available_years, Banking.available_years(user_id))
      |> assign(:available_months, Banking.available_months(user_id))
      |> assign(:banks, Banking.available_banks(user_id))
      |> load_banking_data()
      |> then(fn s -> if s.assigns.rec_loaded, do: load_recurring_data(s), else: s end)

    {:noreply, socket}
  end

  defp assign_today(socket) do
    scope = socket.assigns.current_scope
    accounts = OpenFinance.list_accounts(scope)

    assign(socket, :today, %{
      accounts: accounts,
      totals: OpenFinance.totals(accounts),
      calendar: OpenFinance.coverage_calendar(scope),
      collected_at: OpenFinance.last_collected_at(scope)
    })
  end

  # ── Data Loading: Banking ──

  defp load_recurring_data(socket) do
    window =
      case socket.assigns.rec_window do
        "12" -> 12
        "all" -> :all
        _ -> 6
      end

    analysis =
      Banking.recurring_analysis(socket.assigns.current_scope.user.id,
        window: window,
        bank: socket.assigns.rec_bank,
        statement_type: socket.assigns.rec_type
      )

    socket
    |> assign(:rec_analysis, analysis)
    |> assign(:rec_chart, rec_chart_data(analysis))
    |> assign(:rec_loaded, true)
  end

  defp rec_chart_data(analysis) do
    analysis.monthly
    |> Enum.map(fn m ->
      {_year, month} = m.ym

      %{
        label: Banking.month_name_short(month),
        income: to_float(m.fixed),
        expenses: to_float(m.variable)
      }
    end)
    |> Jason.encode!()
  end

  defp load_banking_data(socket) do
    %{
      selected_year: year,
      selected_month: month,
      view_mode: view_mode,
      selected_bank: bank,
      selected_type: st_type,
      selected_txn_type: txn_type,
      available_years: available_years,
      current_scope: scope
    } = socket.assigns

    user_id = scope.user.id
    opts = bank_opts(bank) ++ type_opts(st_type) ++ txn_type_opts(txn_type)

    summary =
      case view_mode do
        "total" -> Banking.all_time_summary(user_id, opts)
        "year" -> Banking.yearly_summary(user_id, year, opts)
        _ -> Banking.monthly_summary(user_id, year, month, opts)
      end

    daily =
      case view_mode do
        "month" -> Banking.daily_spending(user_id, year, month, opts)
        _ -> []
      end

    all_monthly_ie =
      case view_mode do
        "total" ->
          available_years
          |> Enum.flat_map(fn y ->
            Banking.monthly_income_expenses(user_id, y, opts)
            |> Enum.map(&Map.put(&1, :year, y))
          end)

        _ ->
          Banking.monthly_income_expenses(user_id, year, opts)
      end

    yearly_spending =
      case view_mode do
        "total" ->
          all_monthly_ie
          |> Enum.group_by(& &1.year)
          |> Enum.map(fn {yr, items} ->
            %{
              year: yr,
              expenses:
                Enum.reduce(items, Decimal.new(0), fn i, acc -> Decimal.add(acc, i.expenses) end)
            }
          end)
          |> Enum.sort_by(& &1.year)

        _ ->
          []
      end

    monthly_ie =
      case view_mode do
        "total" -> all_monthly_ie
        "year" -> all_monthly_ie
        _ -> Enum.filter(all_monthly_ie, &(&1.month == month))
      end

    uncat_count = Banking.uncategorized_count(user_id)

    expense_avg =
      case view_mode do
        "total" -> calculate_yearly_avg(summary, available_years)
        "year" -> calculate_monthly_avg(summary, all_monthly_ie)
        _ -> calculate_daily_avg(summary, year, month)
      end

    top_category = calculate_top_category(summary)

    installment_opts =
      case view_mode do
        "total" -> opts
        "year" -> opts
        _ -> opts ++ [year: year, month: month]
      end

    installment_summary = Banking.installment_projection_summary(user_id, installment_opts)

    installment_projections =
      Banking.monthly_installment_projections(user_id, 12, installment_opts)

    socket
    |> assign(:summary, summary)
    |> assign(:daily_spending, daily)
    |> assign(:monthly_ie, monthly_ie)
    |> assign(:yearly_spending, yearly_spending)
    |> assign(:uncategorized_count, uncat_count)
    |> assign(:expense_avg, expense_avg)
    |> assign(:top_category, top_category)
    |> assign(:installment_summary, installment_summary)
    |> assign(:installment_projections, installment_projections)
    |> assign(
      :goals_progress,
      case view_mode do
        "month" -> Banking.goals_progress(user_id, year, month)
        _ -> []
      end
    )
  end

  defp bank_opts("all"), do: []
  defp bank_opts(bank), do: [bank: bank]

  defp type_opts("all"), do: []
  defp type_opts(type), do: [statement_type: type]

  defp txn_type_opts("all"), do: []
  defp txn_type_opts(type), do: [type: type]

  defp calculate_yearly_avg(summary, available_years) do
    case length(available_years) do
      0 -> Decimal.new(0)
      n -> Decimal.div(summary.total_expenses, n) |> Decimal.round(2)
    end
  end

  defp calculate_daily_avg(summary, year, month) do
    days_in_month = Date.days_in_month(Date.new!(year, month, 1))
    Decimal.div(summary.total_expenses, days_in_month) |> Decimal.round(2)
  end

  defp calculate_monthly_avg(summary, monthly_ie) do
    months_with_expenses =
      Enum.count(monthly_ie, fn m -> Decimal.gt?(m.expenses, Decimal.new(0)) end)

    case months_with_expenses do
      0 -> Decimal.new(0)
      n -> Decimal.div(summary.total_expenses, n) |> Decimal.round(2)
    end
  end

  defp calculate_top_category(summary) do
    case summary.by_category do
      [top | _] ->
        name =
          case top.category do
            nil -> "Sem Categoria"
            cat -> cat.name
          end

        pct =
          case Decimal.compare(summary.total_expenses, 0) do
            :gt ->
              top.total
              |> Decimal.div(summary.total_expenses)
              |> Decimal.mult(100)
              |> Decimal.round(1)
              |> Decimal.to_string()

            _ ->
              "0"
          end

        "#{name} (#{pct}%)"

      [] ->
        "—"
    end
  end

  # ── URL Helpers ──

  # URL para Transações respeitando os filtros da aba de despesas fixas (banco e
  # fonte), em vez do período do bancário. Mostra todo o histórico do comerciante.
  defp rec_transactions_url(assigns, extra) do
    base =
      %{}
      |> then(fn p ->
        if assigns.rec_bank != "all", do: Map.put(p, :bank, assigns.rec_bank), else: p
      end)
      |> then(fn p ->
        if assigns.rec_type != "all", do: Map.put(p, :statement_type, assigns.rec_type), else: p
      end)

    qs =
      base
      |> Map.merge(extra)
      |> Enum.reject(fn {_k, v} -> v in [nil, "", "all"] end)
      |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)
      |> Enum.join("&")

    "/transactions?#{qs}"
  end

  defp transactions_url(assigns, extra \\ %{}) do
    %{
      selected_year: year,
      selected_month: month,
      view_mode: mode,
      selected_bank: bank,
      selected_type: st_type
    } = assigns

    base =
      %{}
      |> then(fn p -> if bank != "all", do: Map.put(p, :bank, bank), else: p end)
      |> then(fn p -> if st_type != "all", do: Map.put(p, :statement_type, st_type), else: p end)

    base =
      case mode do
        "month" ->
          date_from = Date.new!(year, month, 1)
          date_to = Date.end_of_month(date_from)
          Map.merge(base, %{date_from: date_from, date_to: date_to})

        "year" ->
          Map.merge(base, %{date_from: Date.new!(year, 1, 1), date_to: Date.new!(year, 12, 31)})

        "total" ->
          base
      end

    params = Map.merge(base, extra)

    qs =
      params
      |> Enum.reject(fn {_k, v} -> v in [nil, "", "all"] end)
      |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)
      |> Enum.join("&")

    "/transactions?#{qs}"
  end

  defp txn_url(assigns, txn) do
    transactions_url(assigns, %{search: txn.description})
  end

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <.page_header title="Painel" subtitle="Visão geral das suas finanças" />

        <.tabs>
          <:tab
            label="Resumo"
            icon="hero-banknotes"
            active={@tab != "recurring"}
            event="switch_tab"
            value="banking"
          />
          <:tab
            label="Despesas fixas"
            icon="hero-arrow-path"
            active={@tab == "recurring"}
            event="switch_tab"
            value="recurring"
          />
        </.tabs>

        <%= cond do %>
          <% @tab == "recurring" -> %>
            {render_recurring_tab(assigns)}
          <% true -> %>
            <OpenFinanceComponents.today
              :if={@today.accounts != []}
              accounts={@today.accounts}
              totals={@today.totals}
              calendar={@today.calendar}
              collected_at={@today.collected_at}
            />
            {render_banking_tab(assigns)}
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # ── Recurring Expenses Tab Render ──

  defp render_recurring_tab(assigns) do
    ~H"""
    <.filter_bar id="recurring-filters">
      <.chip_group label="Janela">
        <.chip
          :for={{label, value} <- [{"6 meses", "6"}, {"12 meses", "12"}]}
          active={@rec_window == value}
          phx-click="rec_set_window"
          phx-value-window={value}
        >
          {label}
        </.chip>
      </.chip_group>
      <.bank_filter banks={@banks} selected={@rec_bank} event="rec_select_bank" />
      <.source_filter selected={@rec_type} event="rec_select_type" />
    </.filter_bar>

    <.empty_state
      :if={@rec_analysis.total_months == 0}
      id="recurring-empty"
      icon="hero-arrow-path"
      title="Nenhuma despesa encontrada nesse período"
    >
      <:action>
        <.button navigate={~p"/upload"} variant="secondary" size="sm">Importar extratos</.button>
      </:action>
    </.empty_state>

    <div :if={@rec_analysis.total_months != 0}>
      <div class="mb-6 grid grid-cols-2 gap-3 sm:gap-4">
        <.stat_tile
          id="rec-fixed-avg"
          label="Fixas por mês"
          value={format_currency(@rec_analysis.avg_fixed)}
          tone={:fixa}
          caption={"#{length(@rec_analysis.fixed)} recorrente(s)"}
        />
        <.stat_tile
          id="rec-variable-avg"
          label="Variáveis por mês"
          value={format_currency(@rec_analysis.avg_variable)}
          tone={:variavel}
          caption={"#{@rec_analysis.total_months} meses analisados"}
        />
      </div>

      <.card title="Fixas vs variáveis por mês" spaced={false} class="mb-6">
        <div
          id="recurring-chart"
          phx-hook="IncomeExpensesChart"
          data-monthly={@rec_chart}
          data-income-label="Fixas"
          data-expenses-label="Variáveis"
          data-income-fill="fill-(--ui-fixa)"
          data-expenses-fill="fill-(--ui-variavel)"
          data-income-color="bg-(--ui-fixa)"
          data-expenses-color="bg-(--ui-variavel)"
        >
        </div>
      </.card>

      <.card
        id="recurring-list"
        title="Despesas fixas"
        spaced={false}
      >
        <:aside>
          <.tag kind="neutro">{length(@rec_analysis.fixed)}</.tag>
        </:aside>
        <p :if={@rec_analysis.fixed == []} class="ui-body ui-text-secondary">
          Nenhuma despesa fixa na janela selecionada. Abra Transações, filtre seus lançamentos e
          marque as despesas que devem entrar como fixas.
        </p>
        <div :if={@rec_analysis.fixed != []} class="-mx-2 flex flex-col">
          <.link
            :for={item <- @rec_analysis.fixed}
            navigate={rec_transactions_url(assigns, %{search: item.name, type: "debit"})}
            class="ui-rounded-box flex cursor-pointer items-center gap-3 px-2 py-2 transition-colors hover:bg-base-300"
          >
            <div class="min-w-0 flex-1">
              <div class="ui-body truncate font-medium">{item.name}</div>
              <div class="ui-help mt-0.5 flex items-center gap-2">
                <.tag kind="neutro">{item.months_present}/{item.total_months} meses</.tag>
                <span :if={item.typical_day}>dia {item.typical_day}</span>
              </div>
            </div>
            <div class="hidden shrink-0 sm:block">
              {render_rec_category(assigns, item.category)}
            </div>
            <div class="shrink-0 text-right">
              <.money value={item.avg_amount} class="ui-body font-medium" />
              <div class="ui-caption">por mês</div>
            </div>
            <.icon name="hero-chevron-right" class="ui-text-tertiary size-4 shrink-0" />
          </.link>
        </div>
      </.card>
    </div>
    """
  end

  defp render_rec_category(assigns, category) do
    assigns = assign(assigns, :cat, category)

    ~H"""
    <.category_icon :if={@cat} category={@cat} />
    <span :if={!@cat} class="ui-text-tertiary">—</span>
    """
  end

  # ── Banking Tab Render ──

  attr :title, :string, required: true
  attr :text, :string, required: true

  defp empty_chart_card(assigns) do
    ~H"""
    <.card title={@title} spaced={false}>
      <p class="ui-help">{@text}</p>
    </.card>
    """
  end

  defp render_banking_tab(assigns) do
    ~H"""
    <.filter_bar :if={@available_years != []} id="banking-filters">
      <.period_filter
        years={@available_years}
        selected_year={if @view_mode == "total", do: nil, else: @selected_year}
        months={months_for_year(@available_months, @selected_year)}
        selected_month={if @view_mode == "month", do: @selected_month}
        all_years
        all_years_active={@view_mode == "total"}
        all_months_active={@view_mode in ["year", "total"]}
      />
      <.bank_filter banks={@banks} selected={@selected_bank} />
      <.source_filter selected={@selected_type} event="select_type" />
      <.movement_filter selected={@selected_txn_type} />
    </.filter_bar>

    <.empty_state
      :if={@summary.transaction_count == 0}
      id="dashboard-empty"
      icon="hero-chart-bar"
      title="Nenhuma transação encontrada"
      text="Importe um extrato bancário para começar."
    >
      <:action>
        <.button navigate={~p"/upload"} variant="primary" icon="hero-cloud-arrow-up">
          Importar extratos
        </.button>
      </:action>
    </.empty_state>

    <div :if={@summary.transaction_count > 0}>
      <%!-- Stat Cards --%>
      <div class="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3 sm:gap-4 lg:grid-cols-6">
        <.stat_tile
          id="stat-income"
          label="Receitas"
          value={if @summary.income_count == 0, do: "—", else: format_currency(@summary.total_income)}
          tone={:receita}
          muted={@summary.income_count == 0}
          caption={
            if @summary.income_count == 0,
              do: "Sem receitas no período",
              else: "#{@summary.income_count} transações"
          }
          navigate={if @summary.income_count > 0, do: transactions_url(assigns, %{type: "credit"})}
        />
        <.stat_tile
          id="stat-expenses"
          label="Despesas"
          value={format_currency(@summary.total_expenses)}
          tone={:despesa}
          caption={
            "#{@summary.expense_count} transações" <>
              if(@summary.refund_count > 0, do: " (#{@summary.refund_count} est.)", else: "")
          }
          navigate={transactions_url(assigns, %{type: "debit"})}
        />
        <.stat_tile
          id="stat-investments"
          label="Investimentos"
          value={
            if @summary.investment_count == 0,
              do: "—",
              else: format_currency(@summary.total_investments)
          }
          tone={:investimento}
          muted={@summary.investment_count == 0}
          caption={
            if @summary.investment_count == 0,
              do: "Sem investimentos no período",
              else: "#{@summary.investment_count} transações"
          }
          navigate={
            if @summary.investment_count > 0, do: transactions_url(assigns, %{type: "investment"})
          }
        />
        <.stat_tile
          id="stat-balance"
          label="Saldo livre"
          value={if @summary.income_count == 0, do: "—", else: format_currency(@summary.balance)}
          tone={if Decimal.compare(@summary.balance, 0) == :lt, do: :despesa, else: :receita}
          muted={@summary.income_count == 0}
          caption={
            cond do
              @summary.income_count == 0 -> "Sem receitas para saldo"
              @uncategorized_count > 0 -> "#{@uncategorized_count} sem categoria"
              true -> "Categorizado"
            end
          }
          navigate={if @summary.income_count > 0, do: transactions_url(assigns)}
        />
        <.stat_tile
          id="stat-average"
          label={
            case @view_mode do
              "total" -> "Média anual"
              "year" -> "Média mensal"
              _ -> "Média diária"
            end
          }
          value={format_currency(@expense_avg)}
          caption="em despesas"
          navigate={transactions_url(assigns, %{type: "debit"})}
        />
        <.stat_tile
          id="stat-count"
          label="Transações"
          value={@summary.transaction_count}
          caption={@top_category}
          navigate={transactions_url(assigns)}
        />
      </div>

      <.notice :if={@uncategorized_count > 0} id="uncategorized-notice" tone={:warning} class="mb-6">
        Você tem {@uncategorized_count} transações sem categoria.
        <:action>
          <.button navigate={~p"/transactions?filter=uncategorized"} variant="secondary" size="sm">
            Categorizar
          </.button>
        </:action>
      </.notice>

      <%!-- Goals Progress --%>
      <.card
        :if={@goals_progress != [] and @view_mode == "month"}
        id="dashboard-goals"
        title="Metas do mês"
        spaced={false}
        class="mb-6"
      >
        <:aside>
          <.link navigate={~p"/goals"} class="ui-help link link-primary no-underline">
            Ver todas
          </.link>
        </:aside>
        <div class="flex flex-col gap-3">
          <div :for={gp <- @goals_progress} class="flex items-center gap-3">
            <span class="ui-help w-20 truncate sm:w-24" title={goal_short_label(gp.goal)}>
              {goal_short_label(gp.goal)}
            </span>
            <div class="flex-1">
              <div class="h-2.5 w-full rounded-full bg-base-300">
                <div
                  class={"h-2.5 rounded-full transition-all #{goal_bar_color(gp.status)}"}
                  style={"width: #{min(gp.pct, 100)}%"}
                />
              </div>
            </div>
            <span class="ui-help whitespace-nowrap">
              {format_currency(gp.current)} / {format_currency(gp.target)}
            </span>
            <span class={"ui-help w-10 text-right font-bold #{goal_text_color(gp.status)}"}>
              {gp.pct}%
            </span>
          </div>
        </div>
      </.card>

      <%!-- Charts: Category + Daily/Monthly --%>
      <div class="mb-6 grid grid-cols-1 gap-4 sm:gap-6 lg:grid-cols-2">
        <%= if @selected_txn_type == "credit" do %>
          <.empty_chart_card
            title="Despesas por categoria"
            text="Sem dados para o filtro selecionado"
          />
        <% else %>
          <.card title="Despesas por categoria" spaced={false}>
            <div
              id="category-chart"
              phx-hook="CategoryChart"
              data-categories={category_chart_data(assigns)}
            >
              <div class="flex flex-col gap-3">
                <div
                  :for={item <- @summary.by_category}
                  phx-click="toggle-category"
                  phx-value-id={if item.category, do: to_string(item.category.id), else: "nil"}
                  class={[
                    "ui-rounded-box -mx-2 flex cursor-pointer select-none items-center gap-3 px-2 py-1 transition-colors",
                    if(category_excluded?(item.category, @excluded_categories),
                      do: "ui-text-tertiary",
                      else: "hover:bg-base-300"
                    )
                  ]}
                >
                  <div
                    class="size-3 shrink-0 rounded-full"
                    style={"background-color: #{category_color(item.category)}"}
                  />
                  <span
                    class={[
                      "ui-body flex-1 truncate",
                      category_excluded?(item.category, @excluded_categories) && "line-through"
                    ]}
                    title={if item.category, do: item.category.name, else: "Sem categoria"}
                  >
                    {if item.category, do: item.category.name, else: "Sem categoria"}
                  </span>
                  <.money value={item.total} class="ui-body font-medium" />
                  <span class="ui-help">
                    {percentage(item.total, @summary.total_expenses)}%
                  </span>
                </div>
                <div :if={MapSet.size(@excluded_categories) > 0}>
                  <.button
                    type="button"
                    variant="ghost"
                    size="sm"
                    phx-click="reset-categories"
                  >
                    Mostrar todas
                  </.button>
                </div>
              </div>
            </div>
          </.card>
        <% end %>

        <%!-- Daily Chart (month view) --%>
        <%= if @selected_txn_type == "credit" do %>
          <.empty_chart_card
            :if={@view_mode == "month"}
            title="Gastos diários"
            text="Sem dados para o filtro selecionado"
          />
        <% else %>
          <.card
            :if={@view_mode == "month" and @daily_spending != []}
            title="Gastos diários"
            spaced={false}
          >
            <div
              id="daily-chart"
              phx-hook="DailyChart"
              data-daily={daily_chart_data(assigns)}
            >
              <div class="flex flex-col gap-1">
                <div
                  :for={day <- @daily_spending}
                  class="flex cursor-pointer items-center gap-2"
                  data-day-date={Calendar.strftime(day.date, "%d/%m")}
                  data-day-value={day.total}
                >
                  <span class="ui-help w-10">{Calendar.strftime(day.date, "%d/%m")}</span>
                  <div class="h-4 flex-1 overflow-hidden rounded-full bg-base-300">
                    <div
                      class="h-full rounded-full bg-(--ui-despesa)/70 transition-all"
                      style={"width: #{bar_width(day.total, @daily_spending)}%"}
                    />
                  </div>
                  <.money value={day.total} class="ui-help w-20 text-right font-medium" />
                </div>
              </div>
            </div>
          </.card>
        <% end %>

        <%!-- Yearly Spending Chart (total view) --%>
        <%= if @selected_txn_type == "credit" do %>
          <.empty_chart_card
            :if={@view_mode == "total"}
            title="Gastos por ano"
            text="Sem dados para o filtro selecionado"
          />
        <% else %>
          <.card
            :if={@view_mode == "total" and @yearly_spending != []}
            title="Gastos por ano"
            spaced={false}
          >
            <div
              id="yearly-spending-chart"
              phx-hook="DailyChart"
              data-daily={yearly_spending_chart_data(assigns)}
            >
              <div class="flex flex-col gap-1">
                <div :for={item <- @yearly_spending} class="flex items-center gap-2">
                  <span class="ui-help w-10">{item.year}</span>
                  <div class="h-4 flex-1 overflow-hidden rounded-full bg-base-300">
                    <div
                      class="h-full rounded-full bg-(--ui-despesa)/70 transition-all"
                      style={"width: #{yearly_bar_width(item.expenses, @yearly_spending)}%"}
                    />
                  </div>
                  <.money value={item.expenses} class="ui-help w-20 text-right font-medium" />
                </div>
              </div>
            </div>
          </.card>
        <% end %>

        <%!-- Monthly Spending Chart (year view) --%>
        <%= if @selected_txn_type == "credit" do %>
          <.empty_chart_card
            :if={@view_mode == "year"}
            title="Gastos mensais"
            text="Sem dados para o filtro selecionado"
          />
        <% else %>
          <.card :if={@view_mode == "year"} title="Gastos mensais" spaced={false}>
            <div
              id="monthly-spending-chart"
              phx-hook="DailyChart"
              data-daily={monthly_spending_chart_data(assigns)}
            >
              <div class="flex flex-col gap-1">
                <div :for={item <- @monthly_ie} class="flex items-center gap-2">
                  <span class="ui-help w-10">{Banking.month_name_short(item.month)}</span>
                  <div class="h-4 flex-1 overflow-hidden rounded-full bg-base-300">
                    <div
                      class="h-full rounded-full bg-(--ui-despesa)/70 transition-all"
                      style={"width: #{monthly_bar_width(item.expenses, @monthly_ie)}%"}
                    />
                  </div>
                  <.money value={item.expenses} class="ui-help w-20 text-right font-medium" />
                </div>
              </div>
            </div>
          </.card>
        <% end %>
      </div>

      <%!-- Maiores receitas / maiores despesas --%>
      <div class="mb-6 grid grid-cols-1 gap-4 sm:gap-6 lg:grid-cols-2">
        <%= if @selected_txn_type == "debit" or @summary.income_count == 0 do %>
          <.empty_chart_card
            title="Maiores receitas"
            text={
              if @selected_txn_type == "debit",
                do: "Sem dados para o filtro selecionado",
                else: "Sem receitas no período"
            }
          />
        <% else %>
          <.card title="Maiores receitas" spaced={false}>
            <div class="-mx-2 flex flex-col">
              <.link
                :for={txn <- Enum.take(@summary.top_income, 10)}
                navigate={txn_url(assigns, txn)}
                class="ui-rounded-box flex items-center gap-3 px-2 py-1 transition-colors hover:bg-base-300"
              >
                <span class="ui-help w-12">{Calendar.strftime(txn.date, "%d/%m")}</span>
                <span class="ui-body flex-1 truncate" title={txn.description}>
                  {txn.description}
                </span>
                <.category_icon :if={txn.category} category={txn.category} />
                <.money
                  value={Decimal.abs(txn.amount)}
                  tone={:receita}
                  class="ui-body font-medium"
                />
              </.link>
            </div>
          </.card>
        <% end %>

        <%= if @selected_txn_type == "credit" or @summary.expense_count == 0 do %>
          <.empty_chart_card
            title="Maiores despesas"
            text={
              if @selected_txn_type == "credit",
                do: "Sem dados para o filtro selecionado",
                else: "Sem despesas no período"
            }
          />
        <% else %>
          <.card title="Maiores despesas" spaced={false}>
            <div class="-mx-2 flex flex-col">
              <.link
                :for={txn <- Enum.take(@summary.top_expenses, 10)}
                navigate={txn_url(assigns, txn)}
                class="ui-rounded-box flex items-center gap-3 px-2 py-1 transition-colors hover:bg-base-300"
              >
                <span class="ui-help w-12">{Calendar.strftime(txn.date, "%d/%m")}</span>
                <span class="ui-body flex-1 truncate" title={txn.description}>
                  {txn.description}
                </span>
                <.category_icon :if={txn.category} category={txn.category} />
                <.money
                  value={Decimal.abs(txn.amount)}
                  tone={:despesa}
                  class="ui-body font-medium"
                />
              </.link>
            </div>
          </.card>
        <% end %>
      </div>

      <%!-- Receitas vs despesas --%>
      <%= cond do %>
        <% @selected_txn_type != "all" -> %>
          <div class="mb-6">
            <.empty_chart_card
              title="Receitas vs despesas"
              text="Sem dados para o filtro selecionado"
            />
          </div>
        <% @summary.income_count == 0 -> %>
          <div class="mb-6">
            <.empty_chart_card title="Receitas vs despesas" text="Sem receitas no período" />
          </div>
        <% @monthly_ie != [] -> %>
          <.card title="Receitas vs despesas" spaced={false} class="mb-6">
            <:aside>
              <div class="flex items-center gap-3">
                <.money value={@summary.balance} tone={:auto} sign class="ui-body font-semibold" />
                <.tag
                  :if={Decimal.compare(@summary.total_income, 0) == :gt}
                  kind={if Decimal.compare(@summary.balance, 0) == :lt, do: "erro", else: "ativo"}
                >
                  {income_expense_pct(@summary)}
                </.tag>
              </div>
            </:aside>
            <div
              id="income-expenses-chart"
              phx-hook="IncomeExpensesChart"
              data-monthly={ie_chart_data(assigns)}
            >
            </div>
          </.card>
        <% true -> %>
      <% end %>

      <%!-- Installments --%>
      <div
        :if={
          @installment_summary.active_count > 0 and @selected_type != "extrato" and
            @selected_txn_type != "credit"
        }
        class="mb-8"
      >
        <div class="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-3 sm:gap-4">
          <.stat_tile
            id="stat-installments-active"
            label="Parcelas ativas"
            value={@installment_summary.active_count}
            caption="parceladas"
          />
          <.stat_tile
            id="stat-installments-month"
            label="Parcelas do mês"
            value={format_currency(@installment_summary.this_month_total)}
            tone={:despesa}
            caption="por mês"
          />
          <.stat_tile
            id="stat-installments-remaining"
            label="Total restante"
            value={format_currency(@installment_summary.total_remaining)}
            tone={:despesa}
            caption="futuras"
          />
        </div>

        <.card id="installments-card" title="Parcelas ativas" spaced={false} class="mb-6">
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Descrição</th>
                  <th>Categoria</th>
                  <th>Valor por mês</th>
                  <th>Progresso</th>
                  <th class="text-right">Restante</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={txn <- @installment_summary.installments} class="hover">
                  <td class="ui-body max-w-xs truncate" title={txn.description}>
                    <.link navigate={txn_url(assigns, txn)} class="hover:underline">
                      {txn.description}
                    </.link>
                  </td>
                  <td>
                    <.category_icon :if={txn.category} category={txn.category} />
                  </td>
                  <td>
                    <.money value={Decimal.abs(txn.amount)} class="ui-body font-medium" />
                  </td>
                  <td>
                    <div class="flex items-center gap-2">
                      <progress
                        class="progress progress-primary w-20"
                        value={txn.installment_current}
                        max={txn.installment_total}
                      />
                      <span class="ui-help">
                        {txn.installment_current}/{txn.installment_total}
                      </span>
                    </div>
                  </td>
                  <td class="text-right">
                    <.money
                      value={
                        Decimal.mult(
                          Decimal.abs(txn.amount),
                          txn.installment_total - txn.installment_current
                        )
                      }
                      tone={:despesa}
                      class="ui-body font-medium"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.card>

        <.card
          :if={@installment_projections != []}
          title="Projeção de parcelas"
          spaced={false}
        >
          <div
            id="projection-chart"
            phx-hook="ProjectionChart"
            data-projections={projection_chart_data(@installment_projections)}
          >
          </div>
        </.card>
      </div>
    </div>
    """
  end

  # ── Shared Helpers ──

  defp toggle_set(set, val) do
    if MapSet.member?(set, val), do: MapSet.delete(set, val), else: MapSet.put(set, val)
  end

  defp months_for_year(available_months, year) do
    available_months
    |> Enum.filter(fn {y, _m} -> y == year end)
    |> Enum.map(fn {_y, m} -> m end)
    |> Enum.sort()
  end

  defp format_currency(amount), do: Grana.Money.format(amount)

  defp percentage(part, total) do
    case Decimal.compare(total, 0) do
      :gt ->
        part |> Decimal.div(total) |> Decimal.mult(100) |> Decimal.round(1) |> Decimal.to_string()

      _ ->
        "0"
    end
  end

  # ── Banking Formatting Helpers ──

  defp income_expense_pct(summary) do
    income = summary.total_income
    expenses = summary.total_expenses

    cond do
      Decimal.compare(income, 0) == :gt ->
        diff = Decimal.sub(income, expenses)
        pct_dec = diff |> Decimal.div(income) |> Decimal.mult(100) |> Decimal.round(1)

        if Decimal.compare(diff, 0) != :lt do
          "economizou #{Decimal.to_string(pct_dec)}%"
        else
          "#{pct_dec |> Decimal.abs() |> Decimal.to_string()}% acima da receita"
        end

      true ->
        "—"
    end
  end

  defp category_color(nil), do: "#9CA3AF"
  defp category_color(category), do: category.color || "#9CA3AF"

  defp category_excluded?(category, excluded) do
    cat_id = if category, do: category.id, else: nil
    MapSet.member?(excluded, cat_id)
  end

  defp bar_width(_total, []), do: 0

  defp bar_width(total, daily) do
    max_val =
      daily
      |> Enum.map(& &1.total)
      |> Enum.max(fn -> Decimal.new(1) end)

    case Decimal.compare(max_val, 0) do
      :gt ->
        total
        |> Decimal.div(max_val)
        |> Decimal.mult(100)
        |> Decimal.round(0)
        |> Decimal.to_integer()

      _ ->
        0
    end
  end

  defp yearly_bar_width(_expenses, []), do: 0

  defp yearly_bar_width(expenses, yearly_spending) do
    max_val =
      yearly_spending
      |> Enum.map(& &1.expenses)
      |> Enum.max(fn -> Decimal.new(1) end)

    case Decimal.compare(max_val, 0) do
      :gt ->
        expenses
        |> Decimal.div(max_val)
        |> Decimal.mult(100)
        |> Decimal.round(0)
        |> Decimal.to_integer()

      _ ->
        0
    end
  end

  defp monthly_bar_width(_expenses, []), do: 0

  defp monthly_bar_width(expenses, monthly_ie) do
    max_val =
      monthly_ie
      |> Enum.map(& &1.expenses)
      |> Enum.max(fn -> Decimal.new(1) end)

    case Decimal.compare(max_val, 0) do
      :gt ->
        expenses
        |> Decimal.div(max_val)
        |> Decimal.mult(100)
        |> Decimal.round(0)
        |> Decimal.to_integer()

      _ ->
        0
    end
  end

  # ── Banking Chart Data ──

  defp category_chart_data(assigns) do
    excluded = assigns[:excluded_categories] || MapSet.new()

    assigns.summary.by_category
    |> Enum.reject(fn item ->
      cat_id = if item.category, do: item.category.id, else: nil
      MapSet.member?(excluded, cat_id)
    end)
    |> Enum.map(fn item ->
      cat_id = if item.category, do: item.category.id, else: nil
      url_extra = if cat_id, do: %{category_id: cat_id}, else: %{filter: "uncategorized"}

      %{
        name: if(item.category, do: item.category.name, else: "Sem Categoria"),
        value: to_float(item.total),
        color: category_color(item.category),
        url: transactions_url(assigns, Map.put(url_extra, :type, "debit"))
      }
    end)
    |> Jason.encode!()
  end

  defp daily_chart_data(assigns) do
    assigns.daily_spending
    |> Enum.map(fn day ->
      %{
        date: Calendar.strftime(day.date, "%d/%m"),
        value: to_float(day.total),
        url: transactions_url(assigns, %{date_from: day.date, date_to: day.date, type: "debit"})
      }
    end)
    |> Jason.encode!()
  end

  defp yearly_spending_chart_data(assigns) do
    assigns.yearly_spending
    |> Enum.map(fn item ->
      %{
        date: to_string(item.year),
        value: to_float(item.expenses),
        url:
          transactions_url(assigns, %{
            date_from: Date.new!(item.year, 1, 1),
            date_to: Date.new!(item.year, 12, 31),
            type: "debit"
          })
      }
    end)
    |> Jason.encode!()
  end

  defp monthly_spending_chart_data(assigns) do
    assigns.monthly_ie
    |> Enum.map(fn item ->
      date_from = Date.new!(assigns.selected_year, item.month, 1)
      date_to = Date.end_of_month(date_from)

      %{
        date: Banking.month_name_short(item.month),
        value: to_float(item.expenses),
        url: transactions_url(assigns, %{date_from: date_from, date_to: date_to, type: "debit"})
      }
    end)
    |> Jason.encode!()
  end

  defp ie_chart_data(%{view_mode: "total"} = assigns) do
    assigns.monthly_ie
    |> Enum.group_by(& &1.year)
    |> Enum.sort_by(fn {year, _} -> year end)
    |> Enum.map(fn {year, items} ->
      income = Enum.reduce(items, Decimal.new(0), fn i, acc -> Decimal.add(acc, i.income) end)
      expenses = Enum.reduce(items, Decimal.new(0), fn i, acc -> Decimal.add(acc, i.expenses) end)
      base = %{date_from: Date.new!(year, 1, 1), date_to: Date.new!(year, 12, 31)}

      %{
        label: to_string(year),
        income: to_float(income),
        expenses: to_float(expenses),
        income_url: transactions_url(assigns, Map.put(base, :type, "credit")),
        expenses_url: transactions_url(assigns, Map.put(base, :type, "debit"))
      }
    end)
    |> Jason.encode!()
  end

  defp ie_chart_data(assigns) do
    assigns.monthly_ie
    |> Enum.map(fn item ->
      date_from = Date.new!(assigns.selected_year, item.month, 1)
      date_to = Date.end_of_month(date_from)
      base = %{date_from: date_from, date_to: date_to}

      %{
        label: Banking.month_name_short(item.month),
        income: to_float(item.income),
        expenses: to_float(item.expenses),
        income_url: transactions_url(assigns, Map.put(base, :type, "credit")),
        expenses_url: transactions_url(assigns, Map.put(base, :type, "debit"))
      }
    end)
    |> Jason.encode!()
  end

  defp projection_chart_data(projections) do
    projections
    |> Enum.map(fn item ->
      %{
        label: item.label,
        value: to_float(item.total)
      }
    end)
    |> Jason.encode!()
  end

  # ── Goal Helpers ──

  defp goal_short_label(%{type: "category_limit", category: %{name: name}}), do: name
  defp goal_short_label(%{type: type}), do: FinancialGoal.type_label(type)

  defp goal_bar_color(:on_track), do: "bg-(--ui-receita)"
  defp goal_bar_color(:achieved), do: "bg-(--ui-receita)"
  defp goal_bar_color(:warning), do: "bg-warning"
  defp goal_bar_color(:exceeded), do: "bg-(--ui-despesa)"
  defp goal_bar_color(:behind), do: "bg-(--ui-despesa)"
  defp goal_bar_color(_), do: "bg-primary"

  defp goal_text_color(:on_track), do: "ui-money-receita"
  defp goal_text_color(:achieved), do: "ui-money-receita"
  defp goal_text_color(:warning), do: "text-warning"
  defp goal_text_color(:exceeded), do: "ui-money-despesa"
  defp goal_text_color(:behind), do: "ui-money-despesa"
  defp goal_text_color(_), do: ""

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(nil), do: 0.0

  defp to_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end
end
