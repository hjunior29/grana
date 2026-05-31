defmodule GranaWeb.DashboardLive do
  use GranaWeb, :live_view

  alias Grana.Banking
  alias Grana.Banking.FinancialGoal
  alias Grana.Investments
  alias Grana.Investments.{Constants, Institution}

  # ── Mount ──

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    Banking.ensure_default_categories(user_id)

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
      # Investment state (lazy loaded on first tab switch)
      |> assign(:inv_loaded, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = params["tab"] || "banking"

    socket =
      case tab do
        "investments" ->
          socket
          |> then(fn s ->
            if s.assigns[:inv_loaded],
              do: s,
              else: s |> init_inv_data() |> load_inv_data()
          end)
          |> apply_inv_url_params(params)
          |> assign(:tab, "investments")

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

  # ── Events: Shared (dispatched by tab) ──

  def handle_event("select_view_total", _params, socket) do
    case socket.assigns.tab do
      "banking" ->
        socket
        |> assign(:view_mode, "total")
        |> load_banking_data()
        |> then(&{:noreply, &1})

      "investments" ->
        socket
        |> assign(:inv_view_mode, "total")
        |> assign(:inv_selected_month, nil)
        |> load_inv_data()
        |> then(&{:noreply, push_inv_patch(&1)})
    end
  end

  def handle_event("select_year", %{"year" => year_str}, socket) do
    year = GranaWeb.Params.to_int(year_str, Date.utc_today().year)

    case socket.assigns.tab do
      "banking" ->
        socket
        |> assign(:selected_year, year)
        |> assign(:view_mode, "year")
        |> load_banking_data()
        |> then(&{:noreply, &1})

      "investments" ->
        socket
        |> assign(:inv_selected_year, year)
        |> assign(:inv_selected_month, nil)
        |> assign(:inv_view_mode, "year")
        |> load_inv_data()
        |> then(&{:noreply, push_inv_patch(&1)})
    end
  end

  def handle_event("select_month", %{"month" => "all"}, socket) do
    case socket.assigns.tab do
      "banking" ->
        socket
        |> assign(:view_mode, "year")
        |> load_banking_data()
        |> then(&{:noreply, &1})

      "investments" ->
        socket
        |> assign(:inv_selected_month, nil)
        |> assign(:inv_view_mode, "year")
        |> load_inv_data()
        |> then(&{:noreply, push_inv_patch(&1)})
    end
  end

  def handle_event("select_month", %{"month" => month_str}, socket) do
    month = GranaWeb.Params.to_int(month_str, 0)

    case socket.assigns.tab do
      "banking" ->
        socket
        |> assign(:selected_month, month)
        |> assign(:view_mode, "month")
        |> load_banking_data()
        |> then(&{:noreply, &1})

      "investments" ->
        socket
        |> assign(:inv_selected_month, month)
        |> assign(:inv_view_mode, "month")
        |> load_inv_data()
        |> then(&{:noreply, push_inv_patch(&1)})
    end
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

  # ── Events: Investments Only ──

  def handle_event("select_institution", %{"institution" => inst}, socket) do
    socket =
      socket
      |> assign(:inv_selected_institution, inst)
      |> load_inv_data()

    {:noreply, push_inv_patch(socket)}
  end

  def handle_event("select_asset_type", %{"type" => type}, socket) do
    socket =
      socket
      |> assign(:inv_selected_asset_type, type)
      |> load_inv_data()

    {:noreply, push_inv_patch(socket)}
  end

  def handle_event("toggle-asset", %{"id" => id}, socket) do
    excluded = toggle_set(socket.assigns.inv_excluded_assets, id)
    {:noreply, assign(socket, :inv_excluded_assets, excluded)}
  end

  def handle_event("reset-assets", _params, socket) do
    {:noreply, assign(socket, :inv_excluded_assets, MapSet.new())}
  end

  # ── Data Loading: Banking ──

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

  # ── Data Loading: Investments ──

  defp init_inv_data(socket) do
    user_id = socket.assigns.current_scope.user.id

    inv_years = Investments.available_years(user_id)
    inv_months = Investments.available_months(user_id)

    institutions =
      Investments.available_institutions(user_id)
      |> Enum.map(fn inst -> %{inst | logo_path: Institution.logo_url(inst)} end)

    asset_types = Investments.available_asset_types(user_id)

    {year, month, view_mode} =
      case inv_months do
        [{y, m} | _] ->
          {y, m, "month"}

        [] ->
          case inv_years do
            [] -> {Date.utc_today().year, nil, "total"}
            years -> {List.last(years), nil, "year"}
          end
      end

    socket
    |> assign(:inv_available_years, inv_years)
    |> assign(:inv_available_months, inv_months)
    |> assign(:inv_institutions, institutions)
    |> assign(:inv_asset_types, asset_types)
    |> assign(:inv_selected_year, year)
    |> assign(:inv_selected_month, month)
    |> assign(:inv_view_mode, view_mode)
    |> assign(:inv_selected_institution, "all")
    |> assign(:inv_selected_asset_type, "all")
    |> assign(:inv_excluded_assets, MapSet.new())
    |> assign(:inv_loaded, true)
  end

  defp load_inv_data(socket) do
    %{
      inv_selected_year: year,
      inv_selected_month: month,
      inv_view_mode: view_mode,
      inv_selected_institution: inst,
      inv_selected_asset_type: asset_type,
      current_scope: scope
    } = socket.assigns

    user_id = scope.user.id

    cumulative_opts =
      case view_mode do
        "total" ->
          []

        "year" ->
          [date_to: Date.new!(year, 12, 31)]

        "month" ->
          date_start = Date.new!(year, month, 1)
          [date_to: Date.end_of_month(date_start)]
      end
      |> maybe_add(:institution_id, inst)
      |> maybe_add(:asset_type, asset_type)
      # Only hit the brapi API when the socket is connected; the disconnected
      # static render serves cached quotes so it never blocks on external HTTP.
      |> Keyword.put(:allow_fetch, connected?(socket))

    period_opts =
      case view_mode do
        "total" ->
          []

        "year" ->
          [date_from: Date.new!(year, 1, 1), date_to: Date.new!(year, 12, 31)]

        "month" ->
          date_start = Date.new!(year, month, 1)
          [date_from: date_start, date_to: Date.end_of_month(date_start)]
      end
      |> maybe_add(:institution_id, inst)
      |> maybe_add(:asset_type, asset_type)

    summary = Investments.portfolio_with_market_data(user_id, cumulative_opts)
    period_summary = Investments.portfolio_summary(user_id, period_opts)

    filter_opts =
      []
      |> maybe_add(:institution_id, inst)
      |> maybe_add(:asset_type, asset_type)

    activity = Investments.period_activity(user_id, view_mode, year, month, filter_opts)

    # Replace NF holdings with period-based saldo
    nf_period_holding =
      period_summary.holdings
      |> Enum.find(fn h -> h.type == "nota_fiscal" and h.is_active end)

    merged_holdings =
      summary.holdings
      |> Enum.reject(fn h -> h.type == "nota_fiscal" end)
      |> then(fn holdings ->
        case nf_period_holding do
          %{} = h ->
            enriched =
              Map.merge(h, %{
                current_price: nil,
                current_value: h.net_total,
                gain_loss: Decimal.new(0),
                gain_loss_pct: nil,
                change_pct: nil,
                logo_url: nil
              })

            holdings ++ [enriched]

          nil ->
            holdings
        end
      end)

    merged_summary = %{summary | holdings: merged_holdings}

    socket
    |> assign(:inv_summary, merged_summary)
    |> assign(:inv_period_proventos, period_summary.proventos)
    |> assign(:inv_period_dividends, period_summary.dividends)
    |> assign(:inv_period_proventos_by_asset, period_summary.proventos_by_asset)
    |> assign(:inv_activity, activity)
  end

  # ── URL Helpers ──

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

  defp inv_transactions_url(assigns, extra) do
    %{
      inv_selected_year: year,
      inv_selected_month: month,
      inv_view_mode: mode,
      inv_selected_institution: inst,
      inv_selected_asset_type: asset_type
    } = assigns

    {skip_dates, extra} = Map.pop(extra, :skip_dates, false)

    base =
      %{tab: "investments"}
      |> then(fn p -> if inst != "all", do: Map.put(p, :institution_id, inst), else: p end)
      |> then(fn p ->
        if asset_type != "all", do: Map.put(p, :asset_type, asset_type), else: p
      end)

    base =
      if skip_dates do
        base
      else
        case mode do
          "month" ->
            date_from = Date.new!(year, month, 1)
            date_to = Date.end_of_month(date_from)
            Map.merge(base, %{date_from: date_from, date_to: date_to})

          "year" ->
            Map.merge(base, %{
              date_from: Date.new!(year, 1, 1),
              date_to: Date.new!(year, 12, 31)
            })

          "total" ->
            base
        end
      end

    params = Map.merge(base, extra)

    qs =
      params
      |> Enum.reject(fn {_k, v} -> v in [nil, "", "all"] end)
      |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)
      |> Enum.join("&")

    "/transactions?#{qs}"
  end

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-4 sm:mb-8 text-center sm:text-left">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Dashboard</h1>
          <p class="text-xs sm:text-sm opacity-60 mt-1">Visão geral das suas finanças</p>
        </div>

        <div role="tablist" class="tabs tabs-border mb-6">
          <button
            role="tab"
            phx-click="switch_tab"
            phx-value-tab="banking"
            class={["tab", @tab == "banking" && "tab-active"]}
          >
            <.icon name="hero-banknotes" class="size-4 mr-1" /> Bancário
          </button>
          <button
            role="tab"
            phx-click="switch_tab"
            phx-value-tab="investments"
            class={["tab", @tab == "investments" && "tab-active"]}
          >
            <.icon name="hero-chart-bar" class="size-4 mr-1" /> Investimentos
          </button>
        </div>

        <%= if @tab == "banking" do %>
          {render_banking_tab(assigns)}
        <% else %>
          {render_investments_tab(assigns)}
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # ── Banking Tab Render ──

  defp render_banking_tab(assigns) do
    ~H"""
    <div :if={@available_years != []} class="mb-4 sm:mb-6 space-y-2">
      <%!-- Row 1: Year + Month --%>
      <div class="flex flex-wrap items-center gap-1 sm:gap-2">
        <div class="flex gap-1">
          <button
            phx-click="select_view_total"
            class={["btn btn-xs sm:btn-sm", (@view_mode == "total" && "btn-primary") || "btn-ghost"]}
          >
            Todos
          </button>
          <button
            :for={y <- @available_years}
            phx-click="select_year"
            phx-value-year={y}
            class={[
              "btn btn-xs sm:btn-sm",
              (@view_mode != "total" && y == @selected_year && "btn-primary") || "btn-ghost"
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
            class={["btn btn-xs", (@view_mode in ["year", "total"] && "btn-primary") || "btn-ghost"]}
          >
            Todos
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
      <div class="grid grid-cols-3 lg:grid-cols-6 gap-2 sm:gap-4 mb-4 sm:mb-8">
        <%= if @summary.income_count == 0 do %>
          <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 opacity-40">
            <div class="stat-title text-xs">Receitas</div>
            <div class="stat-value text-sm sm:text-lg">—</div>
            <div class="stat-desc text-xs">Sem receitas no período</div>
          </div>
        <% else %>
          <.link
            navigate={transactions_url(assigns, %{type: "credit"})}
            class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
          >
            <div class="stat-title text-xs">Receitas</div>
            <div class="stat-value text-success text-sm sm:text-lg">
              {format_currency(@summary.total_income)}
            </div>
            <div class="stat-desc text-xs">
              {@summary.income_count} transações
            </div>
          </.link>
        <% end %>

        <.link
          navigate={transactions_url(assigns, %{type: "debit"})}
          class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
        >
          <div class="stat-title text-xs">Despesas</div>
          <div class="stat-value text-error text-sm sm:text-lg">
            {format_currency(@summary.total_expenses)}
          </div>
          <div class="stat-desc text-xs">
            {@summary.expense_count} transações{if @summary.refund_count > 0,
              do: " (#{@summary.refund_count} est.)",
              else: ""}
          </div>
        </.link>

        <%= if @summary.investment_count == 0 do %>
          <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 opacity-40">
            <div class="stat-title text-xs">Investimentos</div>
            <div class="stat-value text-sm sm:text-lg">—</div>
            <div class="stat-desc text-xs">Sem invest. no período</div>
          </div>
        <% else %>
          <.link
            navigate={transactions_url(assigns, %{type: "investment"})}
            class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
          >
            <div class="stat-title text-xs">Investimentos</div>
            <div class="stat-value text-info text-sm sm:text-lg">
              {format_currency(@summary.total_investments)}
            </div>
            <div class="stat-desc text-xs">
              {@summary.investment_count} transações
            </div>
          </.link>
        <% end %>

        <%= if @summary.income_count == 0 do %>
          <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 opacity-40">
            <div class="stat-title text-xs">Saldo Livre</div>
            <div class="stat-value text-sm sm:text-lg">—</div>
            <div class="stat-desc text-xs">Sem receitas para saldo</div>
          </div>
        <% else %>
          <.link
            navigate={transactions_url(assigns)}
            class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
          >
            <div class="stat-title text-xs">Saldo Livre</div>
            <div class={[
              "stat-value text-sm sm:text-lg",
              (Decimal.compare(@summary.balance, 0) == :lt && "text-error") || "text-success"
            ]}>
              {format_currency(@summary.balance)}
            </div>
            <div class="stat-desc text-xs">
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
          <div class="stat-title text-xs">
            {case @view_mode do
              "total" -> "Média Anual"
              "year" -> "Média Mensal"
              _ -> "Média Diária"
            end}
          </div>
          <div class="stat-value text-sm sm:text-lg">
            {format_currency(@expense_avg)}
          </div>
          <div class="stat-desc text-xs">em despesas</div>
        </.link>

        <.link
          navigate={transactions_url(assigns)}
          class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
        >
          <div class="stat-title text-xs">Transações</div>
          <div class="stat-value text-sm sm:text-lg">
            {@summary.transaction_count}
          </div>
          <div class="stat-desc text-xs truncate" title={@top_category}>{@top_category}</div>
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

      <%!-- Goals Progress --%>
      <div
        :if={@goals_progress != [] and @view_mode == "month"}
        class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6"
      >
        <div class="flex items-center justify-between mb-3">
          <h3 class="font-semibold text-sm sm:text-base">Metas do Mês</h3>
          <.link navigate={~p"/goals"} class="text-xs text-primary hover:underline">
            Ver todas
          </.link>
        </div>
        <div class="space-y-3">
          <div :for={gp <- @goals_progress} class="flex items-center gap-3">
            <span class="text-xs w-20 sm:w-24 truncate opacity-70" title={goal_short_label(gp.goal)}>
              {goal_short_label(gp.goal)}
            </span>
            <div class="flex-1">
              <div class="w-full bg-base-300 rounded-full h-2.5">
                <div
                  class={"h-2.5 rounded-full transition-all #{goal_bar_color(gp.status)}"}
                  style={"width: #{min(gp.pct, 100)}%"}
                />
              </div>
            </div>
            <span class="text-xs font-medium whitespace-nowrap">
              {format_currency(gp.current)} / {format_currency(gp.target)}
            </span>
            <span class={"text-xs font-bold w-10 text-right #{goal_text_color(gp.status)}"}>
              {gp.pct}%
            </span>
          </div>
        </div>
      </div>

      <%!-- Charts: Category + Daily/Monthly --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6">
        <%= if @selected_txn_type == "credit" do %>
          <div class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center">
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Despesas por Categoria</h3>
              <p class="text-xs opacity-70">Sem dados para o filtro selecionado</p>
            </div>
          </div>
        <% else %>
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
                  <span
                    class={[
                      "flex-1 text-sm truncate",
                      category_excluded?(item.category, @excluded_categories) && "line-through"
                    ]}
                    title={if item.category, do: item.category.name, else: "Sem Categoria"}
                  >
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
        <% end %>

        <%!-- Daily Chart (month view) --%>
        <%= if @selected_txn_type == "credit" do %>
          <div
            :if={@view_mode == "month"}
            class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center"
          >
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Gastos Diários</h3>
              <p class="text-xs opacity-70">Sem dados para o filtro selecionado</p>
            </div>
          </div>
        <% else %>
          <div
            :if={@view_mode == "month" and @daily_spending != []}
            class="card bg-base-200 p-4 sm:p-6"
          >
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
        <% end %>

        <%!-- Yearly Spending Chart (total view) --%>
        <%= if @selected_txn_type == "credit" do %>
          <div
            :if={@view_mode == "total"}
            class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center"
          >
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Gastos por Ano</h3>
              <p class="text-xs opacity-70">Sem dados para o filtro selecionado</p>
            </div>
          </div>
        <% else %>
          <div
            :if={@view_mode == "total" and @yearly_spending != []}
            class="card bg-base-200 p-4 sm:p-6"
          >
            <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Gastos por Ano</h3>
            <div
              id="yearly-spending-chart"
              phx-hook="DailyChart"
              data-daily={yearly_spending_chart_data(assigns)}
            >
              <div class="space-y-1">
                <div :for={item <- @yearly_spending} class="flex items-center gap-2">
                  <span class="text-xs w-10 opacity-60">
                    {item.year}
                  </span>
                  <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
                    <div
                      class="bg-primary h-full rounded-full transition-all"
                      style={"width: #{yearly_bar_width(item.expenses, @yearly_spending)}%"}
                    />
                  </div>
                  <span class="text-xs font-medium w-20 text-right">
                    {format_currency(item.expenses)}
                  </span>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Monthly Spending Chart (year view) --%>
        <%= if @selected_txn_type == "credit" do %>
          <div
            :if={@view_mode == "year"}
            class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center"
          >
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Gastos Mensais</h3>
              <p class="text-xs opacity-70">Sem dados para o filtro selecionado</p>
            </div>
          </div>
        <% else %>
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
        <% end %>
      </div>

      <%!-- Top Expenses / Top Income --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6">
        <%= if @selected_txn_type == "credit" or @summary.expense_count == 0 do %>
          <div class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center">
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Top Despesas</h3>
              <p class="text-xs opacity-70">
                {if @selected_txn_type == "credit",
                  do: "Sem dados para o filtro selecionado",
                  else: "Sem despesas no período"}
              </p>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-200 p-4 sm:p-6">
            <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Top Despesas</h3>
            <div class="space-y-1">
              <.link
                :for={txn <- Enum.take(@summary.top_expenses, 10)}
                navigate={txn_url(assigns, txn)}
                class="flex items-center gap-3 hover:bg-base-300 rounded-lg px-2 py-1 -mx-2 transition-colors"
              >
                <span class="text-xs opacity-50 w-12">{Calendar.strftime(txn.date, "%d/%m")}</span>
                <span class="flex-1 text-sm truncate" title={txn.description}>{txn.description}</span>
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
        <% end %>

        <%= if @selected_txn_type == "debit" or @summary.income_count == 0 do %>
          <div class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center">
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Top Receitas</h3>
              <p class="text-xs opacity-70">
                {if @selected_txn_type == "debit",
                  do: "Sem dados para o filtro selecionado",
                  else: "Sem receitas no período"}
              </p>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-200 p-4 sm:p-6">
            <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Top Receitas</h3>
            <div class="space-y-1">
              <.link
                :for={txn <- Enum.take(@summary.top_income, 10)}
                navigate={txn_url(assigns, txn)}
                class="flex items-center gap-3 hover:bg-base-300 rounded-lg px-2 py-1 -mx-2 transition-colors"
              >
                <span class="text-xs opacity-50 w-12">{Calendar.strftime(txn.date, "%d/%m")}</span>
                <span class="flex-1 text-sm truncate" title={txn.description}>{txn.description}</span>
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
      <%= if @selected_txn_type != "all" do %>
        <div class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6 opacity-40">
          <div class="flex items-center justify-center py-8">
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Receitas vs Despesas</h3>
              <p class="text-xs opacity-70">Sem dados para o filtro selecionado</p>
            </div>
          </div>
        </div>
      <% else %>
        <%= if @summary.income_count == 0 do %>
          <div class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6 opacity-40">
            <div class="flex items-center justify-center py-8">
              <div class="text-center">
                <h3 class="font-semibold text-sm sm:text-base mb-2">Receitas vs Despesas</h3>
                <p class="text-xs opacity-70">Sem receitas no período</p>
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
              data-monthly={ie_chart_data(assigns)}
            >
            </div>
          </div>
        <% end %>
      <% end %>

      <%!-- Installments --%>
      <div
        :if={
          @installment_summary.active_count > 0 and @selected_type != "extrato" and
            @selected_txn_type != "credit"
        }
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
                  <td class="text-sm max-w-xs truncate" title={txn.description}>
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
            <div class="stat-title text-xs">Parcelas Ativas</div>
            <div class="stat-value text-warning text-sm sm:text-lg">
              {@installment_summary.active_count}
            </div>
            <div class="stat-desc text-xs">parceladas</div>
          </div>

          <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
            <div class="stat-title text-xs">Mensal Parcelas</div>
            <div class="stat-value text-warning text-sm sm:text-lg">
              {format_currency(@installment_summary.this_month_total)}
            </div>
            <div class="stat-desc text-xs">por mês</div>
          </div>

          <div class="stat bg-base-200 rounded-xl p-3 sm:p-4">
            <div class="stat-title text-xs">Total Restante</div>
            <div class="stat-value text-warning text-sm sm:text-lg">
              {format_currency(@installment_summary.total_remaining)}
            </div>
            <div class="stat-desc text-xs">futuras</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Investments Tab Render ──

  defp render_investments_tab(assigns) do
    ~H"""
    <div :if={@inv_available_years != []} class="mb-4 sm:mb-6 space-y-2">
      <%!-- Row 1: Years + Months --%>
      <div class="flex flex-wrap items-center gap-1 sm:gap-2">
        <div class="flex gap-1">
          <button
            phx-click="select_view_total"
            class={[
              "btn btn-xs sm:btn-sm",
              (@inv_view_mode == "total" && "btn-primary") || "btn-ghost"
            ]}
          >
            Todos
          </button>
          <button
            :for={y <- @inv_available_years}
            phx-click="select_year"
            phx-value-year={y}
            class={[
              "btn btn-xs sm:btn-sm",
              (@inv_view_mode != "total" && y == @inv_selected_year && "btn-primary") || "btn-ghost"
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
            class={[
              "btn btn-xs",
              (@inv_view_mode in ["year", "total"] && "btn-primary") || "btn-ghost"
            ]}
          >
            Todos
          </button>
          <button
            :for={m <- months_for_year(@inv_available_months, @inv_selected_year)}
            phx-click="select_month"
            phx-value-month={m}
            class={[
              "btn btn-xs",
              (@inv_view_mode == "month" && m == @inv_selected_month && "btn-primary") || "btn-ghost"
            ]}
          >
            {Banking.month_name_short(m)}
          </button>
        </div>
      </div>

      <%!-- Row 2: Institution + Asset Type --%>
      <div class="flex flex-wrap items-center gap-2 sm:gap-3">
        <div :if={length(@inv_institutions) > 1} class="flex items-center gap-1">
          <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Instituição</span>
          <button
            phx-click="select_institution"
            phx-value-institution="all"
            class={[
              "btn btn-xs",
              (@inv_selected_institution == "all" && "btn-primary") || "btn-ghost"
            ]}
          >
            Todas
          </button>
          <button
            :for={inst <- @inv_institutions}
            phx-click="select_institution"
            phx-value-institution={inst.id}
            class={[
              "btn btn-xs gap-1",
              (to_string(@inv_selected_institution) == to_string(inst.id) && "btn-primary") ||
                "btn-ghost"
            ]}
          >
            <div
              :if={inst.logo_path}
              class="w-4 h-4 rounded-full overflow-hidden bg-base-300 shrink-0"
            >
              <img src={inst.logo_path} alt="" />
            </div>
            <span class="hidden sm:inline">{inst.name}</span>
          </button>
        </div>

        <div :if={length(@inv_asset_types) > 1} class="flex flex-wrap items-center gap-1">
          <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Tipo</span>
          <button
            phx-click="select_asset_type"
            phx-value-type="all"
            class={[
              "btn btn-xs",
              (@inv_selected_asset_type == "all" && "btn-primary") || "btn-ghost"
            ]}
          >
            Todos
          </button>
          <button
            :for={type <- @inv_asset_types}
            phx-click="select_asset_type"
            phx-value-type={type}
            class={[
              "btn btn-xs",
              (@inv_selected_asset_type == type && "btn-primary") || "btn-ghost"
            ]}
          >
            {asset_type_label(type)}
          </button>
        </div>
      </div>
    </div>

    <div :if={@inv_summary.transaction_count == 0} class="text-center py-10 sm:py-16">
      <.icon name="hero-chart-bar" class="size-12 sm:size-16 mx-auto mb-4 opacity-20" />
      <h2 class="text-lg sm:text-xl font-semibold mb-2">Nenhum investimento encontrado</h2>
      <p class="opacity-60 mb-6 text-sm">
        Faça upload de um extrato de investimentos para começar
      </p>
      <.link navigate={~p"/upload"} class="btn btn-primary btn-sm sm:btn-md">
        <.icon name="hero-cloud-arrow-up" class="size-5" /> Upload
      </.link>
    </div>

    <div :if={@inv_summary.transaction_count > 0}>
      <div :if={!@inv_summary.has_quotes} class="alert alert-warning text-xs mb-4">
        <.icon name="hero-exclamation-triangle" class="size-4" />
        <span>Cotações indisponíveis, valores mostram custo-base.</span>
      </div>
      <%!-- Stat Cards --%>
      <% active_count = Enum.count(@inv_summary.holdings, & &1.is_active) %>
      <div class="grid grid-cols-3 lg:grid-cols-6 gap-2 sm:gap-4 mb-4 sm:mb-8">
        <%!-- 1. Patrimônio (cumulative) --%>
        <.link
          navigate={inv_transactions_url(assigns, %{skip_dates: true})}
          class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
        >
          <div class="stat-title text-xs">
            Patrimônio <span :if={@inv_summary.has_quotes} class="ml-1 text-success">●</span>
          </div>
          <div class="stat-value text-info text-sm sm:text-lg">
            {format_currency(@inv_summary.market_value)}
          </div>
          <div class="stat-desc text-xs">
            {if @inv_summary.has_quotes, do: "preço ao vivo", else: "custo-base"}
          </div>
        </.link>

        <%!-- 2. Total Investido (cumulative) --%>
        <.link
          navigate={inv_transactions_url(assigns, %{operation: "compra", skip_dates: true})}
          class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
        >
          <div class="stat-title text-xs">Investido</div>
          <div class="stat-value text-sm sm:text-lg opacity-70">
            {format_currency(@inv_summary.net_position)}
          </div>
          <div class="stat-desc text-xs">custo-base</div>
        </.link>

        <%!-- 3. Ativos (cumulative) --%>
        <.link
          navigate={inv_transactions_url(assigns, %{skip_dates: true})}
          class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
        >
          <div class="stat-title text-xs">Ativos</div>
          <div class="stat-value text-sm sm:text-lg opacity-70">
            {active_count}
          </div>
          <div
            class="stat-desc text-xs truncate"
            title={
              if length(@inv_summary.by_asset_type) > 0,
                do:
                  Enum.map_join(@inv_summary.by_asset_type, ", ", fn t ->
                    "#{t.count} #{asset_type_label(t.asset_type)}"
                  end),
                else: "na carteira"
            }
          >
            {if length(@inv_summary.by_asset_type) > 0,
              do:
                Enum.map_join(@inv_summary.by_asset_type, ", ", fn t ->
                  "#{t.count} #{asset_type_label(t.asset_type)}"
                end),
              else: "na carteira"}
          </div>
        </.link>

        <%!-- 4. Dividendos (period) --%>
        <.link
          navigate={inv_transactions_url(assigns, %{operation: Constants.income_ops_csv()})}
          class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
        >
          <div class="stat-title text-xs">Dividendos</div>
          <div class="stat-value text-success text-sm sm:text-lg">
            {format_currency(@inv_period_dividends)}
          </div>
          <div class="stat-desc text-xs">renda passiva</div>
        </.link>

        <%!-- 5. Lucro em Vendas (period) --%>
        <.link
          navigate={inv_transactions_url(assigns, %{operation: "venda"})}
          class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
        >
          <div class="stat-title text-xs">Lucro em Vendas</div>
          <div class={[
            "stat-value text-sm sm:text-lg",
            if(Decimal.compare(Decimal.sub(@inv_period_proventos, @inv_period_dividends), 0) == :gt,
              do: "text-success",
              else: "opacity-50"
            )
          ]}>
            {format_currency(Decimal.sub(@inv_period_proventos, @inv_period_dividends))}
          </div>
          <div class="stat-desc text-xs">ganho realizado</div>
        </.link>

        <%!-- 6. Rentabilidade (cumulative) --%>
        <.link
          navigate={inv_transactions_url(assigns, %{skip_dates: true})}
          class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all cursor-pointer"
        >
          <div class="stat-title text-xs">Rentabilidade</div>
          <div class={[
            "stat-value text-sm sm:text-lg",
            gain_loss_class(@inv_summary.total_gain_loss)
          ]}>
            {format_currency_signed(@inv_summary.total_gain_loss)}
          </div>
          <div class={[
            "stat-desc text-xs font-medium",
            gain_loss_class(@inv_summary.total_gain_loss)
          ]}>
            {format_pct(@inv_summary.total_gain_loss_pct)}
          </div>
        </.link>
      </div>

      <%!-- Charts Row 1: Carteira por Ativo + Proventos --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6">
        <%!-- Individual Asset Donut --%>
        <%= if @inv_summary.by_asset_individual != [] do %>
          <div class="card bg-base-200 p-4 sm:p-6">
            <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
              Carteira por Ativo
            </h3>
            <div
              id="inv-asset-chart"
              phx-hook="CategoryChart"
              data-categories={inv_individual_asset_chart_data(assigns)}
            >
              <div class="space-y-2">
                <div
                  :for={h <- Enum.take(@inv_summary.by_asset_individual, 10)}
                  phx-click="toggle-asset"
                  phx-value-id={h.ticker || h.name}
                  class={[
                    "flex items-center gap-3 rounded-lg px-2 py-1 -mx-2 transition-all cursor-pointer select-none",
                    if(MapSet.member?(@inv_excluded_assets, h.ticker || h.name),
                      do: "opacity-30",
                      else: "hover:bg-base-300"
                    )
                  ]}
                >
                  <div
                    class="w-3 h-3 rounded-full shrink-0"
                    style={"background-color: #{asset_type_color(h.type)}"}
                  />
                  <div class="flex-1 min-w-0">
                    <span class={[
                      "text-sm font-medium",
                      MapSet.member?(@inv_excluded_assets, h.ticker || h.name) && "line-through"
                    ]}>
                      {h.ticker || h.name}
                    </span>
                    <span class="text-xs opacity-40 ml-1">{asset_type_label(h.type)}</span>
                  </div>
                  <span class="text-sm font-medium">{format_currency(h.current_value)}</span>
                  <span class="text-xs opacity-50 w-10 text-right">
                    {percentage(h.current_value, @inv_summary.market_value)}%
                  </span>
                </div>
                <button
                  :if={MapSet.size(@inv_excluded_assets) > 0}
                  phx-click="reset-assets"
                  class="text-xs text-primary hover:underline mt-1 cursor-pointer"
                >
                  Mostrar todos
                </button>
              </div>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center">
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Carteira por Ativo</h3>
              <p class="text-xs opacity-70">Sem ativos no período</p>
            </div>
          </div>
        <% end %>

        <%!-- Proventos Bar Chart --%>
        <%= if has_proventos?(@inv_activity) do %>
          <div class="card bg-base-200 p-4 sm:p-6">
            <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
              Dividendos e Ganhos
            </h3>
            <div
              id="inv-proventos-chart"
              phx-hook="DailyChart"
              data-daily={inv_proventos_chart_data(assigns)}
              data-bar-fill="fill-success"
            >
              <div class="space-y-1">
                <div
                  :for={a <- @inv_activity}
                  :if={Decimal.compare(a.proventos, 0) == :gt}
                  class="flex items-center gap-2"
                >
                  <span class="text-xs w-10 opacity-60">
                    {format_activity_label(a.key, @inv_view_mode, @inv_selected_month)}
                  </span>
                  <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
                    <div
                      class="bg-success h-full rounded-full transition-all"
                      style={"width: #{activity_bar_width(a.proventos, @inv_activity, :proventos)}%"}
                    />
                  </div>
                  <span class="text-xs font-medium w-20 text-right text-success">
                    {format_currency(a.proventos)}
                  </span>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center">
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Dividendos e Ganhos</h3>
              <p class="text-xs opacity-70">Sem ganhos no período</p>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Charts Row 2: Patrimônio por Tipo + Aportes --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6">
        <%!-- By Asset Type (Donut) --%>
        <%= if @inv_summary.by_asset_type != [] do %>
          <div class="card bg-base-200 p-4 sm:p-6">
            <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
              Patrimônio por Tipo de Ativo
            </h3>
            <div
              id="inv-type-chart"
              phx-hook="CategoryChart"
              data-categories={inv_asset_type_chart_data(assigns)}
            >
              <div class="space-y-3">
                <div
                  :for={item <- @inv_summary.by_asset_type}
                  class="flex items-center gap-3 rounded-lg px-2 py-1 -mx-2 hover:bg-base-300 transition-all"
                >
                  <div
                    class="w-3 h-3 rounded-full shrink-0"
                    style={"background-color: #{asset_type_color(item.asset_type)}"}
                  />
                  <span class="flex-1 text-sm truncate" title={asset_type_label(item.asset_type)}>
                    {asset_type_label(item.asset_type)}
                  </span>
                  <span class="text-sm font-medium">{format_currency(item.total)}</span>
                  <span class="text-xs opacity-50">
                    {percentage(item.total, @inv_summary.market_value)}%
                  </span>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center">
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Patrimônio por Tipo</h3>
              <p class="text-xs opacity-70">Sem ativos no período</p>
            </div>
          </div>
        <% end %>

        <%!-- Aportes Bar Chart --%>
        <%= if has_aportes?(@inv_activity) do %>
          <div class="card bg-base-200 p-4 sm:p-6">
            <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
              Aportes
            </h3>
            <div
              id="inv-aportes-chart"
              phx-hook="DailyChart"
              data-daily={inv_aportes_chart_data(assigns)}
              data-bar-fill="fill-info"
            >
              <div class="space-y-1">
                <div
                  :for={a <- @inv_activity}
                  :if={Decimal.compare(a.aportes, 0) == :gt}
                  class="flex items-center gap-2"
                >
                  <span class="text-xs w-10 opacity-60">
                    {format_activity_label(a.key, @inv_view_mode, @inv_selected_month)}
                  </span>
                  <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
                    <div
                      class="bg-info h-full rounded-full transition-all"
                      style={"width: #{activity_bar_width(a.aportes, @inv_activity, :aportes)}%"}
                    />
                  </div>
                  <span class="text-xs font-medium w-20 text-right">
                    {format_currency(a.aportes)}
                  </span>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-200 p-4 sm:p-6 opacity-40 flex items-center justify-center">
            <div class="text-center">
              <h3 class="font-semibold text-sm sm:text-base mb-2">Aportes</h3>
              <p class="text-xs opacity-70">Sem aportes no período</p>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Holdings Table (cumulative) --%>
      <div
        :if={active_holdings(@inv_summary.holdings) != []}
        class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6"
      >
        <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">Carteira de Ativos</h3>
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>Ativo</th>
                <th>Tipo</th>
                <th class="text-right">Qtd</th>
                <th class="text-right hidden sm:table-cell">Preço Atual</th>
                <th class="text-right">Valor Atual</th>
                <th class="text-right hidden sm:table-cell">Investido</th>
                <th class="text-right">Rent. %</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={h <- Enum.take(active_holdings(@inv_summary.holdings), 30)}
                class="hover cursor-pointer"
                phx-click="chart-navigate"
                phx-value-url={
                  inv_transactions_url(assigns, %{search: h.ticker || h.name, skip_dates: true})
                }
              >
                <td>
                  <div class="flex items-center gap-2">
                    <div
                      :if={h.institution_logo || h.logo_url}
                      class="w-6 h-6 rounded-full overflow-hidden bg-base-300 shrink-0"
                    >
                      <img src={h.institution_logo || h.logo_url} alt="" />
                    </div>
                    <div class="flex flex-col">
                      <span class="font-medium text-sm">{h.ticker || "—"}</span>
                      <span
                        class="text-xs opacity-50 truncate max-w-[120px] sm:max-w-xs"
                        title={h.name}
                      >
                        {h.name}
                      </span>
                    </div>
                  </div>
                </td>
                <td>
                  <span class={["badge badge-sm whitespace-nowrap", asset_type_badge(h.type)]}>
                    {asset_type_label(h.type)}
                  </span>
                </td>
                <td class="text-right text-sm">{format_quantity(h.net_qty)}</td>
                <td class="text-right text-sm hidden sm:table-cell">
                  {if h.current_price, do: format_currency(h.current_price), else: "—"}
                </td>
                <td class="text-right text-sm font-medium text-info whitespace-nowrap">
                  {format_currency(h.current_value)}
                </td>
                <td class="text-right text-sm opacity-60 hidden sm:table-cell">
                  {format_currency(h.net_total)}
                </td>
                <td class={["text-right text-sm font-medium", gain_loss_class(h.gain_loss)]}>
                  {format_pct(h.gain_loss_pct)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Ganhos por Ativo (period-filtered) --%>
      <div :if={@inv_period_proventos_by_asset != []} class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6">
        <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
          Ganhos por Ativo
        </h3>
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>Ativo</th>
                <th>Tipo</th>
                <th class="text-right">Total</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={r <- Enum.take(@inv_period_proventos_by_asset, 20)}
                class="hover cursor-pointer"
                phx-click="chart-navigate"
                phx-value-url={inv_transactions_url(assigns, %{search: r.ticker || r.name})}
              >
                <td>
                  <div class="flex items-center gap-2">
                    <div
                      :if={r.institution_logo}
                      class="w-6 h-6 rounded-full overflow-hidden bg-base-300 shrink-0"
                    >
                      <img src={r.institution_logo} alt="" />
                    </div>
                    <div class="flex flex-col">
                      <span class="font-medium text-sm">{r.ticker || r.name}</span>
                      <span
                        :if={r.ticker && r.ticker != r.name}
                        class="text-xs opacity-50 truncate max-w-xs"
                        title={r.name}
                      >
                        {r.name}
                      </span>
                    </div>
                  </div>
                </td>
                <td>
                  <span class={["badge badge-sm whitespace-nowrap", asset_type_badge(r.type)]}>
                    {asset_type_label(r.type)}
                  </span>
                </td>
                <td class="text-right text-sm font-medium text-success whitespace-nowrap">
                  {format_currency(r.total)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # ── Shared Helpers ──

  defp push_inv_patch(socket) do
    %{
      inv_selected_year: year,
      inv_selected_month: month,
      inv_view_mode: view_mode,
      inv_selected_institution: inst,
      inv_selected_asset_type: asset_type
    } = socket.assigns

    params =
      %{tab: "investments"}
      |> then(fn p -> if view_mode != "month", do: Map.put(p, :inv_view, view_mode), else: p end)
      |> then(fn p -> if year, do: Map.put(p, :inv_year, year), else: p end)
      |> then(fn p -> if month, do: Map.put(p, :inv_month, month), else: p end)
      |> then(fn p -> if inst != "all", do: Map.put(p, :inv_inst, inst), else: p end)
      |> then(fn p -> if asset_type != "all", do: Map.put(p, :inv_type, asset_type), else: p end)

    qs =
      params
      |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)
      |> Enum.join("&")

    push_patch(socket, to: "/dashboard?#{qs}", replace: true)
  end

  defp apply_inv_url_params(socket, params) do
    socket
    |> then(fn s ->
      case params["inv_year"] do
        nil -> s
        y -> assign(s, :inv_selected_year, GranaWeb.Params.to_int(y, Date.utc_today().year))
      end
    end)
    |> then(fn s ->
      case params["inv_month"] do
        nil -> s
        m -> assign(s, :inv_selected_month, GranaWeb.Params.to_int(m, 0))
      end
    end)
    |> then(fn s ->
      case params["inv_view"] do
        nil -> s
        v when v in ["total", "year", "month"] -> assign(s, :inv_view_mode, v)
        _ -> s
      end
    end)
    |> then(fn s ->
      case params["inv_inst"] do
        nil -> s
        i -> assign(s, :inv_selected_institution, i)
      end
    end)
    |> then(fn s ->
      case params["inv_type"] do
        nil -> s
        t -> assign(s, :inv_selected_asset_type, t)
      end
    end)
    |> then(fn s ->
      if params["inv_year"] || params["inv_month"] || params["inv_view"] ||
           params["inv_inst"] || params["inv_type"] do
        load_inv_data(s)
      else
        s
      end
    end)
  end

  defp toggle_set(set, val) do
    if MapSet.member?(set, val), do: MapSet.delete(set, val), else: MapSet.put(set, val)
  end

  defp maybe_add(opts, _key, "all"), do: opts
  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, _key, ""), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp months_for_year(available_months, year) do
    available_months
    |> Enum.filter(fn {y, _m} -> y == year end)
    |> Enum.map(fn {_y, m} -> m end)
    |> Enum.sort()
  end

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
        part |> Decimal.div(total) |> Decimal.mult(100) |> Decimal.round(1) |> Decimal.to_string()

      _ ->
        "0"
    end
  end

  # ── Banking Formatting Helpers ──

  defp bank_logo("nubank"), do: ~p"/images/nubank-logo.png"
  defp bank_logo("bradesco"), do: ~p"/images/bradesco-logo.png"
  defp bank_logo(_), do: ~p"/images/logo-32.png"

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

  defp yearly_spending_chart_data(assigns) do
    assigns.yearly_spending
    |> Enum.map(fn item ->
      %{
        date: to_string(item.year),
        value: Decimal.to_float(item.expenses),
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
        value: Decimal.to_float(item.expenses),
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
        income: Decimal.to_float(income),
        expenses: Decimal.to_float(expenses),
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

  # ── Investment Formatting Helpers ──

  defp format_currency_signed(amount) do
    case Decimal.compare(amount, 0) do
      :lt -> "- R$ #{format_br_number(Decimal.abs(amount))}"
      _ -> "+ R$ #{format_br_number(amount)}"
    end
  end

  defp format_quantity(qty) do
    float = Decimal.to_float(qty)

    if float == Float.round(float),
      do: "#{trunc(float)}",
      else: Decimal.to_string(Decimal.round(qty, 4))
  end

  defp format_pct(nil), do: "—"

  defp format_pct(pct) do
    val = Decimal.round(pct, 2) |> Decimal.to_string()
    sign = if Decimal.compare(pct, 0) != :lt, do: "+", else: ""
    "#{sign}#{val}%"
  end

  defp active_holdings(holdings) do
    Enum.filter(holdings, & &1.is_active)
  end

  defp gain_loss_class(amount) do
    case Decimal.compare(amount, 0) do
      :gt -> "text-success"
      :lt -> "text-error"
      _ -> "opacity-50"
    end
  end

  # defp period_label("total", _year, _month), do: "acumulado"
  # defp period_label("year", year, _month), do: "em #{year}"

  # defp period_label("month", year, month) do
  #   "em #{Banking.month_name_short(month)}/#{year}"
  # end

  defp format_activity_label(key, "total", _month), do: to_string(key)
  defp format_activity_label(key, "year", _month), do: Banking.month_name_short(key)

  defp format_activity_label(day, "month", month) do
    dd = String.pad_leading(to_string(day), 2, "0")
    mm = String.pad_leading(to_string(month), 2, "0")
    "#{dd}/#{mm}"
  end

  defp asset_type_label(type), do: Constants.asset_type_label(type)
  defp asset_type_color(type), do: Constants.asset_type_color(type)
  defp asset_type_badge(type), do: Constants.asset_type_badge(type)

  @individual_colors [
    "#8B5CF6",
    "#3B82F6",
    "#06B6D4",
    "#10B981",
    "#F59E0B",
    "#EF4444",
    "#EC4899",
    "#F97316",
    "#6366F1",
    "#14B8A6"
  ]

  defp individual_color(index),
    do: Enum.at(@individual_colors, rem(index, length(@individual_colors)))

  defp has_proventos?(activity) do
    Enum.any?(activity, fn a -> Decimal.compare(a.proventos, 0) == :gt end)
  end

  defp has_aportes?(activity) do
    Enum.any?(activity, fn a -> Decimal.compare(a.aportes, 0) == :gt end)
  end

  defp activity_bar_width(_value, [], _field), do: 0

  defp activity_bar_width(value, activity, field) do
    max_val =
      activity
      |> Enum.map(&Map.get(&1, field))
      |> Enum.max(fn -> Decimal.new(1) end)

    bar_pct(value, max_val)
  end

  defp bar_pct(value, max_val) do
    case Decimal.compare(max_val, 0) do
      :gt ->
        value
        |> Decimal.div(max_val)
        |> Decimal.mult(100)
        |> Decimal.round(0)
        |> Decimal.to_integer()

      _ ->
        0
    end
  end

  # ── Investment Chart Data ──

  defp inv_activity_date_range(key, assigns) do
    case assigns.inv_view_mode do
      "total" ->
        year = key
        %{date_from: Date.new!(year, 1, 1), date_to: Date.new!(year, 12, 31)}

      "year" ->
        month = key
        date_from = Date.new!(assigns.inv_selected_year, month, 1)
        %{date_from: date_from, date_to: Date.end_of_month(date_from)}

      "month" ->
        day = key
        date = Date.new!(assigns.inv_selected_year, assigns.inv_selected_month, day)
        %{date_from: date, date_to: date}
    end
  end

  defp inv_proventos_chart_data(assigns) do
    assigns.inv_activity
    |> Enum.map(fn a ->
      range = inv_activity_date_range(a.key, assigns)

      %{
        date: format_activity_label(a.key, assigns.inv_view_mode, assigns.inv_selected_month),
        value: Decimal.to_float(a.proventos),
        url:
          inv_transactions_url(
            assigns,
            Map.put(range, :operation, Constants.income_ops_csv())
          )
      }
    end)
    |> Jason.encode!()
  end

  defp inv_aportes_chart_data(assigns) do
    assigns.inv_activity
    |> Enum.map(fn a ->
      range = inv_activity_date_range(a.key, assigns)

      %{
        date: format_activity_label(a.key, assigns.inv_view_mode, assigns.inv_selected_month),
        value: Decimal.to_float(a.aportes),
        url: inv_transactions_url(assigns, Map.put(range, :operation, "compra"))
      }
    end)
    |> Jason.encode!()
  end

  defp inv_individual_asset_chart_data(assigns) do
    excluded = assigns[:inv_excluded_assets] || MapSet.new()
    total = Decimal.to_float(assigns.inv_summary.market_value)

    assigns.inv_summary.by_asset_individual
    |> Enum.reject(fn h -> MapSet.member?(excluded, h.ticker || h.name) end)
    |> Enum.with_index()
    |> Enum.map(fn {h, idx} ->
      search = h.ticker || h.name

      %{
        name: h.ticker || h.name,
        value: Decimal.to_float(h.current_value),
        color: individual_color(idx),
        url: inv_transactions_url(assigns, %{search: search, skip_dates: true})
      }
    end)
    |> then(fn data -> if total > 0, do: data, else: [] end)
    |> Jason.encode!()
  end

  defp inv_asset_type_chart_data(assigns) do
    total = Decimal.to_float(assigns.inv_summary.market_value)

    assigns.inv_summary.by_asset_type
    |> Enum.map(fn item ->
      %{
        name: asset_type_label(item.asset_type),
        value: Decimal.to_float(item.total),
        color: asset_type_color(item.asset_type),
        url: inv_transactions_url(assigns, %{asset_type: item.asset_type, skip_dates: true})
      }
    end)
    |> then(fn data -> if total > 0, do: data, else: [] end)
    |> Jason.encode!()
  end

  # ── Goal Helpers ──

  defp goal_short_label(%{type: "category_limit", category: %{name: name}}), do: name
  defp goal_short_label(%{type: type}), do: FinancialGoal.type_label(type)

  defp goal_bar_color(:on_track), do: "bg-success"
  defp goal_bar_color(:achieved), do: "bg-success"
  defp goal_bar_color(:warning), do: "bg-warning"
  defp goal_bar_color(:exceeded), do: "bg-error"
  defp goal_bar_color(:behind), do: "bg-error"
  defp goal_bar_color(_), do: "bg-primary"

  defp goal_text_color(:on_track), do: "text-success"
  defp goal_text_color(:achieved), do: "text-success"
  defp goal_text_color(:warning), do: "text-warning"
  defp goal_text_color(:exceeded), do: "text-error"
  defp goal_text_color(:behind), do: "text-error"
  defp goal_text_color(_), do: ""
end
