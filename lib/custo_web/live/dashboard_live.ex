defmodule CustoWeb.DashboardLive do
  use CustoWeb, :live_view

  alias Custo.Banking

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

  defp load_data(socket) do
    %{
      selected_year: year,
      selected_month: month,
      view_mode: view_mode,
      selected_bank: bank,
      current_scope: scope
    } = socket.assigns

    user_id = scope.user.id
    opts = bank_opts(bank)

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

    monthly_ie = Banking.monthly_income_expenses(user_id, year)
    uncat_count = Banking.uncategorized_count(user_id)

    daily_avg = calculate_daily_avg(summary, daily)
    top_category = calculate_top_category(summary)

    socket
    |> assign(:summary, summary)
    |> assign(:daily_spending, daily)
    |> assign(:monthly_ie, monthly_ie)
    |> assign(:uncategorized_count, uncat_count)
    |> assign(:daily_avg, daily_avg)
    |> assign(:top_category, top_category)
  end

  defp bank_opts("all"), do: []
  defp bank_opts(bank), do: [bank: bank]

  defp calculate_daily_avg(summary, daily) do
    days_with_spending = length(daily)

    case days_with_spending do
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-8">
          <h1 class="text-3xl font-bold tracking-tight">Dashboard</h1>
          <p class="text-sm opacity-60 mt-1">Visão geral das suas finanças</p>
        </div>

        <div :if={@available_years != []} class="mb-6 space-y-3">
          <div class="flex flex-wrap gap-2">
            <button
              :for={y <- @available_years}
              phx-click="select_year"
              phx-value-year={y}
              class={["btn btn-sm", (y == @selected_year && "btn-primary") || "btn-ghost"]}
            >
              {y}
            </button>
          </div>
          <div class="flex flex-wrap gap-1">
            <button
              phx-click="select_month"
              phx-value-month="all"
              class={["btn btn-xs", (@view_mode == "year" && "btn-secondary") || "btn-ghost"]}
            >
              Ano todo
            </button>
            <button
              :for={m <- months_for_year(@available_months, @selected_year)}
              phx-click="select_month"
              phx-value-month={m}
              class={[
                "btn btn-xs",
                (@view_mode == "month" and m == @selected_month && "btn-primary") || "btn-ghost"
              ]}
            >
              {Banking.month_name_short(m)}
            </button>
          </div>
          <div :if={@banks != []} class="flex flex-wrap gap-1">
            <button
              phx-click="select_bank"
              phx-value-bank="all"
              class={["btn btn-xs", (@selected_bank == "all" && "btn-accent") || "btn-ghost"]}
            >
              Todos os bancos
            </button>
            <button
              :for={b <- @banks}
              phx-click="select_bank"
              phx-value-bank={b}
              class={["btn btn-xs gap-1", (@selected_bank == b && "btn-accent") || "btn-ghost"]}
            >
              <img src={bank_logo(b)} alt="" class="w-4 h-4 rounded-full" />
              {String.capitalize(b)}
            </button>
          </div>
        </div>

        <div :if={@summary.transaction_count == 0} class="text-center py-16">
          <.icon name="hero-chart-bar" class="size-16 mx-auto mb-4 opacity-20" />
          <h2 class="text-xl font-semibold mb-2">Nenhuma transação encontrada</h2>
          <p class="opacity-60 mb-6">Faça upload de um extrato bancário para começar</p>
          <.link navigate={~p"/upload"} class="btn btn-primary">
            <.icon name="hero-cloud-arrow-up" class="size-5" /> Upload
          </.link>
        </div>

        <div :if={@summary.transaction_count > 0}>
          <div class="grid grid-cols-2 md:grid-cols-5 gap-4 mb-8">
            <div class="stat bg-base-200 rounded-xl p-4">
              <div class="stat-title text-xs">Receitas</div>
              <div class="stat-value text-success text-lg">
                {format_currency(@summary.total_income)}
              </div>
              <div class="stat-desc">
                {count_by_type(@summary.transactions, "credit")} transações
              </div>
            </div>

            <div class="stat bg-base-200 rounded-xl p-4">
              <div class="stat-title text-xs">Despesas</div>
              <div class="stat-value text-error text-lg">
                {format_currency(@summary.total_expenses)}
              </div>
              <div class="stat-desc">
                {count_by_type(@summary.transactions, "debit")} transações
              </div>
            </div>

            <div class="stat bg-base-200 rounded-xl p-4">
              <div class="stat-title text-xs">Saldo</div>
              <div class={[
                "stat-value text-lg",
                (Decimal.compare(@summary.balance, 0) == :lt && "text-error") || "text-success"
              ]}>
                {format_currency(@summary.balance)}
              </div>
              <div class="stat-desc">
                {if @uncategorized_count > 0,
                  do: "#{@uncategorized_count} sem categoria",
                  else: "Tudo categorizado"}
              </div>
            </div>

            <div class="stat bg-base-200 rounded-xl p-4">
              <div class="stat-title text-xs">Média Diária</div>
              <div class="stat-value text-lg">
                {format_currency(@daily_avg)}
              </div>
              <div class="stat-desc">em despesas</div>
            </div>

            <div class="stat bg-base-200 rounded-xl p-4">
              <div class="stat-title text-xs">Transações</div>
              <div class="stat-value text-lg">
                {@summary.transaction_count}
              </div>
              <div class="stat-desc truncate">{@top_category}</div>
            </div>
          </div>

          <div :if={@uncategorized_count > 0} class="alert alert-warning mb-6">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <span>Você tem {@uncategorized_count} transações sem categoria.</span>
            <.link navigate={~p"/transactions?filter=uncategorized"} class="btn btn-sm btn-ghost">
              Categorizar
            </.link>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
            <div class="card bg-base-200 p-6">
              <h3 class="font-semibold mb-4">Despesas por Categoria</h3>
              <div
                id="category-chart"
                phx-hook="CategoryChart"
                data-categories={category_chart_data(@summary.by_category)}
              >
                <div class="space-y-3">
                  <div :for={item <- @summary.by_category} class="flex items-center gap-3">
                    <div
                      class="w-3 h-3 rounded-full shrink-0"
                      style={"background-color: #{category_color(item.category)}"}
                    />
                    <span class="flex-1 text-sm truncate">
                      {if item.category, do: item.category.name, else: "Sem Categoria"}
                    </span>
                    <span class="text-sm font-medium">{format_currency(item.total)}</span>
                    <span class="text-xs opacity-50">
                      {percentage(item.total, @summary.total_expenses)}%
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <div :if={@view_mode == "month"} class="card bg-base-200 p-6">
              <h3 class="font-semibold mb-4">Gastos Diários</h3>
              <div
                id="daily-chart"
                phx-hook="DailyChart"
                data-daily={daily_chart_data(@daily_spending)}
              >
                <div class="space-y-1">
                  <div :for={day <- @daily_spending} class="flex items-center gap-2">
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

            <div :if={@view_mode == "year"} class="card bg-base-200 p-6">
              <h3 class="font-semibold mb-4">Top Despesas</h3>
              <div class="space-y-2">
                <div :for={txn <- top_expenses(@summary.transactions, 10)} class="flex items-center gap-3">
                  <span class="text-xs opacity-50 w-12">{Calendar.strftime(txn.date, "%d/%m")}</span>
                  <span class="flex-1 text-sm truncate">{txn.description}</span>
                  <span class="text-sm font-medium text-error">{format_currency(Decimal.abs(txn.amount))}</span>
                </div>
              </div>
            </div>
          </div>

          <div :if={@monthly_ie != []} class="card bg-base-200 p-6 mb-8">
            <h3 class="font-semibold mb-4">Receitas vs Despesas — {@selected_year}</h3>
            <div
              id="income-expenses-chart"
              phx-hook="IncomeExpensesChart"
              data-monthly={monthly_ie_chart_data(@monthly_ie)}
            >
            </div>
          </div>

          <div :if={@view_mode == "month"} class="card bg-base-200 p-6 mb-8">
            <h3 class="font-semibold mb-4">Top Despesas</h3>
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Data</th>
                    <th>Descrição</th>
                    <th>Categoria</th>
                    <th class="text-right">Valor</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={txn <- top_expenses(@summary.transactions, 10)}>
                    <td class="text-sm">{Calendar.strftime(txn.date, "%d/%m")}</td>
                    <td class="text-sm max-w-xs truncate">{txn.description}</td>
                    <td>
                      <span
                        :if={txn.category}
                        class="badge badge-sm"
                        style={"background-color: #{txn.category.color}20; color: #{txn.category.color}; border-color: #{txn.category.color}40"}
                      >
                        {txn.category.name}
                      </span>
                    </td>
                    <td class="text-right text-sm font-medium text-error">
                      {format_currency(Decimal.abs(txn.amount))}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div class="flex justify-center gap-4">
            <.link navigate={~p"/transactions"} class="btn btn-ghost">
              Ver todas as transações <.icon name="hero-arrow-right" class="size-4" />
            </.link>
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

  defp count_by_type(transactions, type) do
    Enum.count(transactions, &(&1.type == type))
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

  defp category_color(nil), do: "#9CA3AF"
  defp category_color(category), do: category.color || "#9CA3AF"

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

  defp top_expenses(transactions, limit) do
    transactions
    |> Enum.filter(&(&1.type == "debit"))
    |> Enum.sort_by(fn t -> Decimal.to_float(Decimal.abs(t.amount)) end, :desc)
    |> Enum.take(limit)
  end

  defp category_chart_data(by_category) do
    by_category
    |> Enum.map(fn item ->
      %{
        name: if(item.category, do: item.category.name, else: "Sem Categoria"),
        value: Decimal.to_float(item.total),
        color: category_color(item.category)
      }
    end)
    |> Jason.encode!()
  end

  defp daily_chart_data(daily) do
    daily
    |> Enum.map(fn day ->
      %{
        date: Calendar.strftime(day.date, "%d/%m"),
        value: Decimal.to_float(day.total)
      }
    end)
    |> Jason.encode!()
  end

  defp monthly_ie_chart_data(monthly_ie) do
    monthly_ie
    |> Enum.map(fn item ->
      %{
        label: Banking.month_name_short(item.month),
        income: Decimal.to_float(item.income),
        expenses: Decimal.to_float(item.expenses)
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
