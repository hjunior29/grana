defmodule GranaWeb.DashboardLive do
  use GranaWeb, :live_view

  alias Grana.Banking

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    Banking.ensure_default_categories(user_id)

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
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_year", %{"year" => year_str}, socket) do
    year = String.to_integer(year_str)

    socket =
      socket
      |> assign(:selected_year, year)
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("select_month", %{"month" => "all"}, socket) do
    socket =
      socket
      |> assign(:view_mode, "year")
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("select_month", %{"month" => month_str}, socket) do
    month = String.to_integer(month_str)

    socket =
      socket
      |> assign(:selected_month, month)
      |> assign(:view_mode, "month")
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("select_bank", %{"bank" => bank}, socket) do
    socket =
      socket
      |> assign(:selected_bank, bank)
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("select_type", %{"type" => type}, socket) do
    socket =
      socket
      |> assign(:selected_type, type)
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("select_txn_type", %{"txn_type" => txn_type}, socket) do
    socket =
      socket
      |> assign(:selected_txn_type, txn_type)
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("toggle-category", %{"id" => "nil"}, socket) do
    excluded = toggle_set(socket.assigns.excluded_categories, nil)
    {:noreply, assign(socket, :excluded_categories, excluded)}
  end

  def handle_event("toggle-category", %{"id" => id_str}, socket) do
    excluded = toggle_set(socket.assigns.excluded_categories, String.to_integer(id_str))
    {:noreply, assign(socket, :excluded_categories, excluded)}
  end

  def handle_event("reset-categories", _params, socket) do
    {:noreply, assign(socket, :excluded_categories, MapSet.new())}
  end

  def handle_event("chart-navigate", %{"url" => url}, socket) do
    {:noreply, push_navigate(socket, to: url)}
  end

  defp load_data(socket) do
    %{
      selected_year: year,
      selected_month: month,
      view_mode: view_mode,
      selected_bank: bank,
      selected_type: st_type,
      selected_txn_type: txn_type,
      current_scope: scope
    } = socket.assigns

    user_id = scope.user.id
    opts = bank_opts(bank) ++ type_opts(st_type) ++ txn_type_opts(txn_type)

    summary =
      case view_mode do
        "year" -> Banking.yearly_summary(user_id, year, opts)
        _ -> Banking.monthly_summary(user_id, year, month, opts)
      end

    daily =
      case view_mode do
        "year" -> []
        _ -> Banking.daily_spending(user_id, year, month, opts)
      end

    all_monthly_ie = Banking.monthly_income_expenses(user_id, year, opts)

    monthly_ie =
      case view_mode do
        "year" -> all_monthly_ie
        _ -> Enum.filter(all_monthly_ie, &(&1.month == month))
      end
    uncat_count = Banking.uncategorized_count(user_id)

    expense_avg =
      case view_mode do
        "year" -> calculate_monthly_avg(summary, all_monthly_ie)
        _ -> calculate_daily_avg(summary, daily)
      end

    top_category = calculate_top_category(summary)

    installment_opts =
      case view_mode do
        "year" -> opts
        _ -> opts ++ [year: year, month: month]
      end

    installment_summary = Banking.installment_projection_summary(user_id, installment_opts)
    installment_projections = Banking.monthly_installment_projections(user_id, 12, installment_opts)

    socket
    |> assign(:summary, summary)
    |> assign(:daily_spending, daily)
    |> assign(:monthly_ie, monthly_ie)
    |> assign(:uncategorized_count, uncat_count)
    |> assign(:expense_avg, expense_avg)
    |> assign(:top_category, top_category)
    |> assign(:installment_summary, installment_summary)
    |> assign(:installment_projections, installment_projections)
  end

  defp bank_opts("all"), do: []
  defp bank_opts(bank), do: [bank: bank]

  defp type_opts("all"), do: []
  defp type_opts(type), do: [statement_type: type]

  defp txn_type_opts("all"), do: []
  defp txn_type_opts(type), do: [type: type]

  defp calculate_daily_avg(summary, daily) do
    days_with_spending = length(daily)

    case days_with_spending do
      0 -> Decimal.new(0)
      n -> Decimal.div(summary.total_expenses, n) |> Decimal.round(2)
    end
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

  # --- URL helpers ---

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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-4 sm:mb-8 text-center sm:text-left">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Dashboard</h1>
          <p class="text-xs sm:text-sm opacity-60 mt-1">Visão geral das suas finanças</p>
        </div>

        <div :if={@available_years != []} class="mb-4 sm:mb-6 space-y-2">
          <%!-- Row 1: Year + Month --%>
          <div class="flex flex-wrap items-center gap-1 sm:gap-2">
            <div class="flex gap-1">
              <button
                :for={y <- @available_years}
                phx-click="select_year"
                phx-value-year={y}
                class={[
                  "btn btn-xs sm:btn-sm",
                  (y == @selected_year && "btn-primary") || "btn-ghost"
                ]}
              >
                {y}
              </button>
            </div>
            <div class="divider divider-horizontal mx-0 hidden sm:flex"></div>
            <div class="flex flex-wrap gap-1">
              <button
                phx-click="select_month"
                phx-value-month="all"
                class={["btn btn-xs", (@view_mode == "year" && "btn-primary") || "btn-ghost"]}
              >
                Ano
              </button>
              <button
                :for={m <- months_for_year(@available_months, @selected_year)}
                phx-click="select_month"
                phx-value-month={m}
                class={[
                  "btn btn-xs",
                  ((@view_mode == "month" and m == @selected_month) && "btn-primary") ||
                    "btn-ghost"
                ]}
              >
                {Banking.month_name_short(m)}
              </button>
            </div>
          </div>

          <%!-- Row 2: Bank + Statement Type + Transaction Type --%>
          <div class="flex flex-wrap items-center gap-2 sm:gap-3">
            <div :if={@banks != []} class="flex items-center gap-1">
              <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Banco</span>
              <button
                phx-click="select_bank"
                phx-value-bank="all"
                class={["btn btn-xs", (@selected_bank == "all" && "btn-primary") || "btn-ghost"]}
              >
                Todos
              </button>
              <button
                :for={b <- @banks}
                phx-click="select_bank"
                phx-value-bank={b}
                class={["btn btn-xs gap-1", (@selected_bank == b && "btn-primary") || "btn-ghost"]}
              >
                <img src={bank_logo(b)} alt="" class="w-4 h-4 rounded-full" />
                <span class="hidden sm:inline">{String.capitalize(b)}</span>
              </button>
            </div>
            <div class="flex items-center gap-1">
              <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Fonte</span>
              <button
                phx-click="select_type"
                phx-value-type="all"
                class={["btn btn-xs", (@selected_type == "all" && "btn-primary") || "btn-ghost"]}
              >
                Todas
              </button>
              <button
                phx-click="select_type"
                phx-value-type="extrato"
                class={[
                  "btn btn-xs gap-1",
                  (@selected_type == "extrato" && "btn-primary") || "btn-ghost"
                ]}
              >
                <.icon name="hero-banknotes" class="size-3" />
                <span class="hidden sm:inline">Extrato</span>
              </button>
              <button
                phx-click="select_type"
                phx-value-type="fatura"
                class={[
                  "btn btn-xs gap-1",
                  (@selected_type == "fatura" && "btn-primary") || "btn-ghost"
                ]}
              >
                <.icon name="hero-credit-card" class="size-3" />
                <span class="hidden sm:inline">Fatura</span>
              </button>
            </div>
            <div class="flex items-center gap-1">
              <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Tipo</span>
              <button
                phx-click="select_txn_type"
                phx-value-txn_type="all"
                class={["btn btn-xs", (@selected_txn_type == "all" && "btn-primary") || "btn-ghost"]}
              >
                Todas
              </button>
              <button
                phx-click="select_txn_type"
                phx-value-txn_type="debit"
                class={[
                  "btn btn-xs gap-1",
                  (@selected_txn_type == "debit" && "btn-primary") || "btn-ghost"
                ]}
              >
                Despesas
              </button>
              <button
                phx-click="select_txn_type"
                phx-value-txn_type="credit"
                class={[
                  "btn btn-xs gap-1",
                  (@selected_txn_type == "credit" && "btn-primary") || "btn-ghost"
                ]}
              >
                Receitas
              </button>
              <button
                phx-click="select_txn_type"
                phx-value-txn_type="investment"
                class={[
                  "btn btn-xs gap-1",
                  (@selected_txn_type == "investment" && "btn-primary") || "btn-ghost"
                ]}
              >
                <span class="hidden sm:inline">Investimentos</span>
                <span class="sm:hidden">Invest.</span>
              </button>
            </div>
          </div>
        </div>

        <div :if={@summary.transaction_count == 0} class="text-center py-10 sm:py-16">
          <.icon name="hero-chart-bar" class="size-12 sm:size-16 mx-auto mb-4 opacity-20" />
          <h2 class="text-lg sm:text-xl font-semibold mb-2">Nenhuma transação encontrada</h2>
          <p class="opacity-60 mb-6 text-sm">Faça upload de um extrato bancário para começar</p>
          <.link navigate={~p"/upload"} class="btn btn-primary btn-sm sm:btn-md">
            <.icon name="hero-cloud-arrow-up" class="size-5" /> Upload
          </.link>
        </div>

        <div :if={@summary.transaction_count > 0}>
          <%!-- Stat Cards --%>
          <div
            class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-2 sm:gap-4 mb-4 sm:mb-8"
          >
            <%= if @summary.income_count == 0 do %>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 opacity-40">
                <div class="stat-title text-[10px] sm:text-xs">Receitas</div>
                <div class="stat-value text-sm sm:text-lg">—</div>
                <div class="stat-desc text-[10px] sm:text-xs">Sem receitas no período</div>
              </div>
            <% else %>
              <.link
                navigate={transactions_url(assigns, %{type: "credit"})}
                class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
              >
                <div class="stat-title text-[10px] sm:text-xs">Receitas</div>
                <div class="stat-value text-success text-sm sm:text-lg">
                  {format_currency(@summary.total_income)}
                </div>
                <div class="stat-desc text-[10px] sm:text-xs">
                  {@summary.income_count} transações
                </div>
              </.link>
            <% end %>

            <.link
              navigate={transactions_url(assigns, %{type: "debit"})}
              class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
            >
              <div class="stat-title text-[10px] sm:text-xs">Despesas</div>
              <div class="stat-value text-error text-sm sm:text-lg">
                {format_currency(@summary.total_expenses)}
              </div>
              <div class="stat-desc text-[10px] sm:text-xs">
                {@summary.expense_count} transações{if @summary.refund_count > 0,
                  do: " (#{@summary.refund_count} est.)",
                  else: ""}
              </div>
            </.link>

            <%= if @summary.investment_count == 0 do %>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 opacity-40">
                <div class="stat-title text-[10px] sm:text-xs">Investimentos</div>
                <div class="stat-value text-sm sm:text-lg">—</div>
                <div class="stat-desc text-[10px] sm:text-xs">Sem invest. no período</div>
              </div>
            <% else %>
              <.link
                navigate={transactions_url(assigns, %{type: "investment"})}
                class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
              >
                <div class="stat-title text-[10px] sm:text-xs">Investimentos</div>
                <div class="stat-value text-info text-sm sm:text-lg">
                  {format_currency(@summary.total_investments)}
                </div>
                <div class="stat-desc text-[10px] sm:text-xs">
                  {@summary.investment_count} transações
                </div>
              </.link>
            <% end %>

            <%= if @summary.income_count == 0 do %>
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 opacity-40">
                <div class="stat-title text-[10px] sm:text-xs">Saldo Livre</div>
                <div class="stat-value text-sm sm:text-lg">—</div>
                <div class="stat-desc text-[10px] sm:text-xs">Sem receitas para saldo</div>
              </div>
            <% else %>
              <.link
                navigate={transactions_url(assigns)}
                class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
              >
                <div class="stat-title text-[10px] sm:text-xs">Saldo Livre</div>
                <div class={[
                  "stat-value text-sm sm:text-lg",
                  (Decimal.compare(@summary.balance, 0) == :lt && "text-error") || "text-success"
                ]}>
                  {format_currency(@summary.balance)}
                </div>
                <div class="stat-desc text-[10px] sm:text-xs">
                  {if @uncategorized_count > 0,
                    do: "#{@uncategorized_count} sem cat.",
                    else: "Categorizado"}
                </div>
              </.link>
            <% end %>

            <.link
              navigate={transactions_url(assigns, %{type: "debit"})}
              class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
            >
              <div class="stat-title text-[10px] sm:text-xs">
                {if @view_mode == "year", do: "Média Mensal", else: "Média Diária"}
              </div>
              <div class="stat-value text-sm sm:text-lg">
                {format_currency(@expense_avg)}
              </div>
              <div class="stat-desc text-[10px] sm:text-xs">em despesas</div>
            </.link>

            <.link
              navigate={transactions_url(assigns)}
              class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
            >
              <div class="stat-title text-[10px] sm:text-xs">Transações</div>
              <div class="stat-value text-sm sm:text-lg">
                {@summary.transaction_count}
              </div>
              <div class="stat-desc text-[10px] sm:text-xs truncate">{@top_category}</div>
            </.link>
          </div>

          <div
            :if={@uncategorized_count > 0}
            class="alert alert-warning mb-6"
          >
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <span>Você tem {@uncategorized_count} transações sem categoria.</span>
            <.link navigate={~p"/transactions?filter=uncategorized"} class="btn btn-sm btn-ghost">
              Categorizar
            </.link>
          </div>

          <%!-- Charts: Category + Daily/Monthly --%>
          <div
            class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6"
          >
            <div class="card bg-base-200 p-4 sm:p-6">
              <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Despesas por Categoria</h3>
              <div
                id="category-chart"
                phx-hook="CategoryChart"
                data-categories={category_chart_data(assigns)}
              >
                <div class="space-y-3">
                  <div
                    :for={item <- @summary.by_category}
                    phx-click="toggle-category"
                    phx-value-id={if item.category, do: to_string(item.category.id), else: "nil"}
                    class={[
                      "flex items-center gap-3 rounded-lg px-2 py-1 -mx-2 transition-all cursor-pointer select-none",
                      if(category_excluded?(item.category, @excluded_categories),
                        do: "opacity-30",
                        else: "hover:bg-base-300"
                      )
                    ]}
                  >
                    <div
                      class="w-3 h-3 rounded-full shrink-0"
                      style={"background-color: #{category_color(item.category)}"}
                    />
                    <span class={[
                      "flex-1 text-sm truncate",
                      category_excluded?(item.category, @excluded_categories) && "line-through"
                    ]}>
                      {if item.category, do: item.category.name, else: "Sem Categoria"}
                    </span>
                    <span class="text-sm font-medium">{format_currency(item.total)}</span>
                    <span class="text-xs opacity-50">
                      {percentage(item.total, @summary.total_expenses)}%
                    </span>
                  </div>
                  <button
                    :if={MapSet.size(@excluded_categories) > 0}
                    phx-click="reset-categories"
                    class="text-xs text-primary hover:underline mt-1 cursor-pointer"
                  >
                    Mostrar todas
                  </button>
                </div>
              </div>
            </div>

            <%!-- Daily Chart (month view) --%>
            <div :if={@view_mode == "month"} class="card bg-base-200 p-4 sm:p-6">
              <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Gastos Diários</h3>
              <div
                id="daily-chart"
                phx-hook="DailyChart"
                data-daily={daily_chart_data(assigns)}
              >
                <div class="space-y-1">
                  <div
                    :for={day <- @daily_spending}
                    class="flex items-center gap-2 cursor-pointer"
                    data-day-date={Calendar.strftime(day.date, "%d/%m")}
                    data-day-value={day.total}
                  >
                    <span class="text-xs w-10 opacity-60">
                      {Calendar.strftime(day.date, "%d/%m")}
                    </span>
                    <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
                      <div
                        class="bg-primary h-full rounded-full transition-all"
                        style={"width: #{bar_width(day.total, @daily_spending)}%"}
                      />
                    </div>
                    <span class="text-xs font-medium w-20 text-right">
                      {format_currency(day.total)}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Monthly Spending Chart (year view) --%>
            <div :if={@view_mode == "year"} class="card bg-base-200 p-4 sm:p-6">
              <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Gastos Mensais</h3>
              <div
                id="monthly-spending-chart"
                phx-hook="DailyChart"
                data-daily={monthly_spending_chart_data(assigns)}
              >
                <div class="space-y-1">
                  <div :for={item <- @monthly_ie} class="flex items-center gap-2">
                    <span class="text-xs w-10 opacity-60">
                      {Banking.month_name_short(item.month)}
                    </span>
                    <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
                      <div
                        class="bg-primary h-full rounded-full transition-all"
                        style={"width: #{monthly_bar_width(item.expenses, @monthly_ie)}%"}
                      />
                    </div>
                    <span class="text-xs font-medium w-20 text-right">
                      {format_currency(item.expenses)}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%!-- Top Expenses / Top Income --%>
          <div
            class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6"
          >
            <div class="card bg-base-200 p-4 sm:p-6">
              <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Top Despesas</h3>
              <div class="space-y-1">
                <.link
                  :for={txn <- top_expenses(@summary.transactions, 10)}
                  navigate={txn_url(assigns, txn)}
                  class="flex items-center gap-3 hover:bg-base-300 rounded-lg px-2 py-1 -mx-2 transition-colors"
                >
                  <span class="text-xs opacity-50 w-12">{Calendar.strftime(txn.date, "%d/%m")}</span>
                  <span class="flex-1 text-sm truncate">{txn.description}</span>
                  <span
                    :if={txn.category}
                    class="badge badge-sm shrink-0"
                    style={"background-color: #{txn.category.color}20; color: #{txn.category.color}; border-color: #{txn.category.color}40"}
                  >
                    {txn.category.name}
                  </span>
                  <span class="text-sm font-medium text-error whitespace-nowrap">
                    {format_currency(Decimal.abs(txn.amount))}
                  </span>
                </.link>
              </div>
            </div>

            <%= if @summary.income_count == 0 do %>
              <div class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center">
                <div class="text-center">
                  <h3 class="font-semibold text-sm sm:text-base mb-2">Top Receitas</h3>
                  <p class="text-xs opacity-70">Sem receitas no período</p>
                </div>
              </div>
            <% else %>
              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Top Receitas</h3>
                <div class="space-y-1">
                  <.link
                    :for={txn <- top_income(@summary.transactions, 10)}
                    navigate={txn_url(assigns, txn)}
                    class="flex items-center gap-3 hover:bg-base-300 rounded-lg px-2 py-1 -mx-2 transition-colors"
                  >
                    <span class="text-xs opacity-50 w-12">{Calendar.strftime(txn.date, "%d/%m")}</span>
                    <span class="flex-1 text-sm truncate">{txn.description}</span>
                    <span
                      :if={txn.category}
                      class="badge badge-sm shrink-0"
                      style={"background-color: #{txn.category.color}20; color: #{txn.category.color}; border-color: #{txn.category.color}40"}
                    >
                      {txn.category.name}
                    </span>
                    <span class="text-sm font-medium text-success whitespace-nowrap">
                      {format_currency(Decimal.abs(txn.amount))}
                    </span>
                  </.link>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Income vs Expenses Chart --%>
          <%= if @summary.income_count == 0 do %>
            <div class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6 opacity-40">
              <div class="flex items-center justify-center py-8">
                <div class="text-center">
                  <h3 class="font-semibold text-sm sm:text-base mb-2">Receitas vs Despesas</h3>
                  <p class="text-xs opacity-70">Sem receitas no período para comparação</p>
                </div>
              </div>
            </div>
          <% else %>
            <div
              :if={@monthly_ie != []}
              class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6"
            >
              <div class="flex flex-wrap items-center justify-between gap-2 mb-4">
                <h3 class="font-semibold text-sm sm:text-base">Receitas vs Despesas</h3>
                <div class="flex items-center gap-3 text-sm">
                  <span class={[
                    "font-semibold",
                    if(Decimal.compare(@summary.balance, 0) == :lt,
                      do: "text-error",
                      else: "text-success"
                    )
                  ]}>
                    {if Decimal.compare(@summary.balance, 0) != :lt, do: "+", else: ""}{format_currency(
                      @summary.balance
                    )}
                  </span>
                  <span
                    :if={Decimal.compare(@summary.total_income, 0) == :gt}
                    class={[
                      "badge badge-sm",
                      if(Decimal.compare(@summary.balance, 0) == :lt,
                        do: "badge-error",
                        else: "badge-success"
                      )
                    ]}
                  >
                    {if Decimal.compare(@summary.balance, 0) != :lt, do: "", else: ""}{income_expense_pct(
                      @summary
                    )}
                  </span>
                </div>
              </div>
              <div
                id="income-expenses-chart"
                phx-hook="IncomeExpensesChart"
                data-monthly={monthly_ie_chart_data(assigns)}
              >
              </div>
            </div>
          <% end %>

          <%!-- Installments --%>
          <div
            :if={@installment_summary.active_count > 0 and @selected_type != "extrato"}
            class="mb-4 sm:mb-8"
          >
            <div class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6">
              <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Parcelas Ativas</h3>
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Descrição</th>
                      <th>Categoria</th>
                      <th>Valor/mês</th>
                      <th>Progresso</th>
                      <th class="text-right">Restante</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={txn <- @installment_summary.installments} class="hover">
                      <td class="text-sm max-w-xs truncate">
                        <.link navigate={txn_url(assigns, txn)} class="hover:underline">
                          {txn.description}
                        </.link>
                      </td>
                      <td>
                        <span
                          :if={txn.category}
                          class="badge badge-sm"
                          style={"background-color: #{txn.category.color}20; color: #{txn.category.color}; border-color: #{txn.category.color}40"}
                        >
                          {txn.category.name}
                        </span>
                      </td>
                      <td class="text-sm font-medium">
                        {format_currency(Decimal.abs(txn.amount))}
                      </td>
                      <td>
                        <div class="flex items-center gap-2">
                          <progress
                            class="progress progress-warning w-20"
                            value={txn.installment_current}
                            max={txn.installment_total}
                          />
                          <span class="text-xs opacity-60">
                            {txn.installment_current}/{txn.installment_total}
                          </span>
                        </div>
                      </td>
                      <td class="text-right text-sm font-medium text-warning">
                        {format_currency(
                          Decimal.mult(
                            Decimal.abs(txn.amount),
                            txn.installment_total - txn.installment_current
                          )
                        )}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>

            <div :if={@installment_projections != []} class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6">
              <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Projeção de Parcelas</h3>
              <div
                id="projection-chart"
                phx-hook="ProjectionChart"
                data-projections={projection_chart_data(@installment_projections)}
              >
              </div>
            </div>

            <div class="grid grid-cols-3 gap-2 sm:gap-4">
              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Parcelas Ativas</div>
                <div class="stat-value text-warning text-sm sm:text-lg">
                  {@installment_summary.active_count}
                </div>
                <div class="stat-desc text-[10px] sm:text-xs">parceladas</div>
              </div>

              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Mensal Parcelas</div>
                <div class="stat-value text-warning text-sm sm:text-lg">
                  {format_currency(@installment_summary.this_month_total)}
                </div>
                <div class="stat-desc text-[10px] sm:text-xs">por mês</div>
              </div>

              <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
                <div class="stat-title text-[10px] sm:text-xs">Total Restante</div>
                <div class="stat-value text-warning text-sm sm:text-lg">
                  {format_currency(@installment_summary.total_remaining)}
                </div>
                <div class="stat-desc text-[10px] sm:text-xs">futuras</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp bank_logo("nubank"), do: ~p"/images/nubank-logo.png"
  defp bank_logo("bradesco"), do: ~p"/images/bradesco-logo.png"
  defp bank_logo(_), do: ~p"/images/logo-32.png"

  defp format_currency(amount) do
    "R$ #{format_br_number(amount)}"
  end

  defp format_br_number(amount) do
    str = amount |> Decimal.round(2) |> Decimal.abs() |> Decimal.to_string(:normal)
    [int_part, dec_part] = String.split(str, ".")
    dec_part = String.pad_trailing(dec_part, 2, "0")

    int_formatted =
      int_part
      |> String.reverse()
      |> String.to_charlist()
      |> Enum.chunk_every(3)
      |> Enum.join(".")
      |> String.reverse()

    sign = if Decimal.compare(amount, 0) == :lt, do: "-", else: ""
    "#{sign}#{int_formatted},#{dec_part}"
  end

  defp percentage(part, total) do
    case Decimal.compare(total, 0) do
      :gt ->
        part
        |> Decimal.div(total)
        |> Decimal.mult(100)
        |> Decimal.round(1)
        |> Decimal.to_string()

      _ ->
        "0"
    end
  end

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

  defp toggle_set(set, val) do
    if MapSet.member?(set, val), do: MapSet.delete(set, val), else: MapSet.put(set, val)
  end

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

  defp top_expenses(transactions, limit) do
    transactions
    |> Enum.filter(&(&1.type == "debit"))
    |> Enum.sort_by(fn t -> Decimal.to_float(Decimal.abs(t.amount)) end, :desc)
    |> Enum.take(limit)
  end

  defp top_income(transactions, limit) do
    transactions
    |> Enum.filter(&(&1.type == "credit"))
    |> Enum.sort_by(fn t -> Decimal.to_float(Decimal.abs(t.amount)) end, :desc)
    |> Enum.take(limit)
  end

  # --- Chart data with URLs ---

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
        value: Decimal.to_float(item.total),
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
        value: Decimal.to_float(day.total),
        url: transactions_url(assigns, %{date_from: day.date, date_to: day.date, type: "debit"})
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
        value: Decimal.to_float(item.expenses),
        url: transactions_url(assigns, %{date_from: date_from, date_to: date_to, type: "debit"})
      }
    end)
    |> Jason.encode!()
  end

  defp monthly_ie_chart_data(assigns) do
    assigns.monthly_ie
    |> Enum.map(fn item ->
      date_from = Date.new!(assigns.selected_year, item.month, 1)
      date_to = Date.end_of_month(date_from)
      base = %{date_from: date_from, date_to: date_to}

      %{
        label: Banking.month_name_short(item.month),
        income: Decimal.to_float(item.income),
        expenses: Decimal.to_float(item.expenses),
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
        value: Decimal.to_float(item.total)
      }
    end)
    |> Jason.encode!()
  end

  defp months_for_year(available_months, year) do
    available_months
    |> Enum.filter(fn {y, _m} -> y == year end)
    |> Enum.map(fn {_y, m} -> m end)
    |> Enum.sort()
  end
end
