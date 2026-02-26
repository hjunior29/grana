defmodule GranaWeb.InvestmentsLive do
  use GranaWeb, :live_view

  alias Grana.Banking
  alias Grana.Investments

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    available_years = Investments.available_years(user_id)
    months = Investments.available_months(user_id)
    alias Grana.Investments.Institution

    institutions =
      Investments.available_institutions(user_id)
      |> Enum.map(fn inst -> %{inst | logo_path: Institution.logo_url(inst)} end)
    asset_types = Investments.available_asset_types(user_id)
    operations = Investments.available_operations(user_id)

    {year, month, view_mode} =
      case months do
        [{y, m} | _] -> {y, m, "month"}
        [] ->
          case available_years do
            [] -> {Date.utc_today().year, nil, "total"}
            years -> {List.last(years), nil, "year"}
          end
      end

    socket =
      socket
      |> assign(:page_title, "Investimentos")
      |> assign(:available_years, available_years)
      |> assign(:available_months, months)
      |> assign(:institutions, institutions)
      |> assign(:user_asset_types, asset_types)
      |> assign(:user_operations, operations)
      |> assign(:selected_year, year)
      |> assign(:selected_month, month)
      |> assign(:view_mode, view_mode)
      |> assign(:selected_institution, "all")
      |> assign(:selected_asset_type, "all")
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_view_total", _params, socket) do
    socket =
      socket
      |> assign(:view_mode, "total")
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("select_year", %{"year" => year_str}, socket) do
    year = String.to_integer(year_str)

    socket =
      socket
      |> assign(:selected_year, year)
      |> assign(:selected_month, nil)
      |> assign(:view_mode, "year")
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("select_month", %{"month" => "all"}, socket) do
    socket =
      socket
      |> assign(:selected_month, nil)
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

  def handle_event("select_institution", %{"institution" => inst}, socket) do
    socket =
      socket
      |> assign(:selected_institution, inst)
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("select_asset_type", %{"type" => type}, socket) do
    socket =
      socket
      |> assign(:selected_asset_type, type)
      |> load_data()

    {:noreply, socket}
  end

  defp load_data(socket) do
    %{
      selected_year: year,
      selected_month: month,
      view_mode: view_mode,
      selected_institution: inst,
      selected_asset_type: asset_type,
      current_scope: scope
    } = socket.assigns

    user_id = scope.user.id

    # Cumulative opts: all transactions up to end of selected period
    cumulative_opts =
      case view_mode do
        "total" -> []
        "year" -> [date_to: Date.new!(year, 12, 31)]
        "month" ->
          date_start = Date.new!(year, month, 1)
          [date_to: Date.end_of_month(date_start)]
      end
      |> maybe_add(:institution_id, inst)
      |> maybe_add(:asset_type, asset_type)

    # Period opts: only transactions within the selected period
    period_opts =
      case view_mode do
        "total" -> []
        "year" -> [date_from: Date.new!(year, 1, 1), date_to: Date.new!(year, 12, 31)]
        "month" ->
          date_start = Date.new!(year, month, 1)
          [date_from: date_start, date_to: Date.end_of_month(date_start)]
      end
      |> maybe_add(:institution_id, inst)
      |> maybe_add(:asset_type, asset_type)

    # Cumulative portfolio (holdings, market value, by_asset_type)
    summary = Investments.portfolio_with_market_data(user_id, cumulative_opts)

    # Period-specific data (dividend payers, period dividends)
    period_summary = Investments.portfolio_summary(user_id, period_opts)

    # Chart data grouped by period
    filter_opts =
      []
      |> maybe_add(:institution_id, inst)
      |> maybe_add(:asset_type, asset_type)

    activity = Investments.period_activity(user_id, view_mode, year, month, filter_opts)

    # Replace NF holdings with period-based saldo (NF is short-term, not cumulative)
    nf_period_holding =
      period_summary.holdings
      |> Enum.find(fn h -> h.type == "nota_fiscal" and h.is_active end)

    merged_holdings =
      summary.holdings
      |> Enum.reject(fn h -> h.type == "nota_fiscal" end)
      |> then(fn holdings ->
        case nf_period_holding do
          %{} = h ->
            enriched = Map.merge(h, %{
              current_price: nil,
              current_value: h.net_total,
              gain_loss: Decimal.new(0),
              gain_loss_pct: Decimal.new(0),
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
    |> assign(:summary, merged_summary)
    |> assign(:period_proventos, period_summary.proventos)
    |> assign(:period_proventos_by_asset, period_summary.proventos_by_asset)
    |> assign(:activity, activity)
  end

  defp maybe_add(opts, _key, "all"), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-4 sm:mb-8 text-center sm:text-left">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Investimentos</h1>
          <p class="text-xs sm:text-sm opacity-60 mt-1">Acompanhe seus investimentos</p>
        </div>

        <div :if={@available_years != []} class="mb-4 sm:mb-6 space-y-2">
          <%!-- Row 1: Years + Months --%>
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
                Ano
              </button>
              <button
                :for={m <- months_for_year(@available_months, @selected_year)}
                phx-click="select_month"
                phx-value-month={m}
                class={[
                  "btn btn-xs",
                  (@view_mode == "month" && m == @selected_month && "btn-primary") || "btn-ghost"
                ]}
              >
                {Banking.month_name_short(m)}
              </button>
            </div>
          </div>

          <%!-- Row 2: Institution + Asset Type --%>
          <div class="flex flex-wrap items-center gap-2 sm:gap-3">
            <div :if={length(@institutions) > 1} class="flex items-center gap-1">
              <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Instituição</span>
              <button
                phx-click="select_institution"
                phx-value-institution="all"
                class={[
                  "btn btn-xs",
                  (@selected_institution == "all" && "btn-primary") || "btn-ghost"
                ]}
              >
                Todas
              </button>
              <button
                :for={inst <- @institutions}
                phx-click="select_institution"
                phx-value-institution={inst.id}
                class={[
                  "btn btn-xs gap-1",
                  (to_string(@selected_institution) == to_string(inst.id) && "btn-primary") ||
                    "btn-ghost"
                ]}
              >
                <div :if={inst.logo_path} class="w-4 h-4 rounded-full overflow-hidden bg-base-300 shrink-0">
                  <img src={inst.logo_path} alt=""/>
                </div>
                <span class="hidden sm:inline">{inst.name}</span>
              </button>
            </div>

            <div :if={length(@user_asset_types) > 1} class="flex flex-wrap items-center gap-1">
              <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Tipo</span>
              <button
                phx-click="select_asset_type"
                phx-value-type="all"
                class={[
                  "btn btn-xs",
                  (@selected_asset_type == "all" && "btn-primary") || "btn-ghost"
                ]}
              >
                Todos
              </button>
              <button
                :for={type <- @user_asset_types}
                phx-click="select_asset_type"
                phx-value-type={type}
                class={[
                  "btn btn-xs",
                  (@selected_asset_type == type && "btn-primary") || "btn-ghost"
                ]}
              >
                {asset_type_label(type)}
              </button>
            </div>
          </div>
        </div>

        <div :if={@summary.transaction_count == 0} class="text-center py-10 sm:py-16">
          <.icon name="hero-chart-bar-square" class="size-12 sm:size-16 mx-auto mb-4 opacity-20" />
          <h2 class="text-lg sm:text-xl font-semibold mb-2">Nenhum investimento encontrado</h2>
          <p class="opacity-60 mb-6 text-sm">
            Faça upload de um extrato de investimentos para começar
          </p>
          <.link navigate={~p"/upload"} class="btn btn-primary btn-sm sm:btn-md">
            <.icon name="hero-cloud-arrow-up" class="size-5" /> Upload
          </.link>
        </div>

        <div :if={@summary.transaction_count > 0}>
          <%!-- Stat Cards --%>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-2 sm:gap-4 mb-4 sm:mb-8">
            <%!-- Patrimônio Atual (cumulative) --%>
            <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all">
              <div class="stat-title text-[10px] sm:text-xs">
                Patrimônio Atual
                <span :if={@summary.has_quotes} class="ml-1 text-success">●</span>
              </div>
              <div class="stat-value text-info text-sm sm:text-lg">
                {format_currency(@summary.market_value)}
              </div>
              <div class="stat-desc text-[10px] sm:text-xs">
                {if @summary.has_quotes, do: "preço ao vivo", else: "custo-base"}
              </div>
            </div>

            <%!-- Proventos (period) --%>
            <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all">
              <div class="stat-title text-[10px] sm:text-xs">Proventos e Resultados</div>
              <div class="stat-value text-success text-sm sm:text-lg">
                {format_currency(@period_proventos)}
              </div>
              <div class="stat-desc text-[10px] sm:text-xs">{period_label(@view_mode, @selected_year, @selected_month)}</div>
            </div>

            <%!-- Total Investido (cumulative) --%>
            <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all">
              <div class="stat-title text-[10px] sm:text-xs">Total Investido</div>
              <div class="stat-value text-sm sm:text-lg opacity-70">
                {format_currency(@summary.net_position)}
              </div>
              <div class="stat-desc text-[10px] sm:text-xs">acumulado</div>
            </div>

            <%!-- Rentabilidade (cumulative) --%>
            <div class="stat bg-base-200 rounded-xl p-3 sm:p-4 hover:scale-[1.03] hover:shadow-lg transition-all">
              <div class="stat-title text-[10px] sm:text-xs">Rentabilidade</div>
              <div class={[
                "stat-value text-sm sm:text-lg",
                gain_loss_class(@summary.total_gain_loss)
              ]}>
                {format_currency_signed(@summary.total_gain_loss)}
              </div>
              <div class={[
                "stat-desc text-[10px] sm:text-xs font-medium",
                gain_loss_class(@summary.total_gain_loss)
              ]}>
                {format_pct(@summary.total_gain_loss_pct)}
              </div>
            </div>
          </div>

          <%!-- Charts Row 1: Carteira por Ativo + Proventos (recebimentos) --%>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6">
            <%!-- Individual Asset Donut --%>
            <%= if @summary.by_asset_individual != [] do %>
              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
                  Carteira por Ativo
                </h3>
                <div
                  id="inv-asset-chart"
                  phx-hook="CategoryChart"
                  data-categories={individual_asset_chart_data(@summary.by_asset_individual, @summary.market_value)}
                >
                  <div class="space-y-2">
                    <div
                      :for={h <- Enum.take(@summary.by_asset_individual, 10)}
                      class="flex items-center gap-3 rounded-lg px-2 py-1 -mx-2 hover:bg-base-300 transition-all"
                    >
                      <div
                        class="w-3 h-3 rounded-full shrink-0"
                        style={"background-color: #{asset_type_color(h.type)}"}
                      />
                      <div class="flex-1 min-w-0">
                        <span class="text-sm font-medium">{h.ticker || h.name}</span>
                        <span class="text-xs opacity-40 ml-1">{asset_type_label(h.type)}</span>
                      </div>
                      <span class="text-sm font-medium">{format_currency(h.current_value)}</span>
                      <span class="text-xs opacity-50 w-10 text-right">
                        {percentage(h.current_value, @summary.market_value)}%
                      </span>
                    </div>
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
            <%= if has_proventos?(@activity) do %>
              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
                  Proventos e Resultados
                </h3>
                <div
                  id="inv-proventos-chart"
                  phx-hook="DailyChart"
                  data-daily={proventos_chart_data(@activity, @view_mode, @selected_month)}
                  data-bar-fill="fill-success"
                >
                  <div class="space-y-1">
                    <div
                      :for={a <- @activity}
                      :if={Decimal.compare(a.proventos, 0) == :gt}
                      class="flex items-center gap-2"
                    >
                      <span class="text-xs w-10 opacity-60">
                        {format_activity_label(a.key, @view_mode, @selected_month)}
                      </span>
                      <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
                        <div
                          class="bg-success h-full rounded-full transition-all"
                          style={"width: #{activity_bar_width(a.proventos, @activity, :proventos)}%"}
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
                  <h3 class="font-semibold text-sm sm:text-base mb-2">Proventos e Resultados</h3>
                  <p class="text-xs opacity-70">Sem proventos no período</p>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Charts Row 2: Patrimônio por Tipo + Aportes --%>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6">
            <%!-- By Asset Type (Donut) --%>
            <%= if @summary.by_asset_type != [] do %>
              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
                  Patrimônio por Tipo de Ativo
                </h3>
                <div
                  id="inv-type-chart"
                  phx-hook="CategoryChart"
                  data-categories={asset_type_chart_data(@summary.by_asset_type, @summary.market_value)}
                >
                  <div class="space-y-3">
                    <div
                      :for={item <- @summary.by_asset_type}
                      class="flex items-center gap-3 rounded-lg px-2 py-1 -mx-2 hover:bg-base-300 transition-all"
                    >
                      <div
                        class="w-3 h-3 rounded-full shrink-0"
                        style={"background-color: #{asset_type_color(item.asset_type)}"}
                      />
                      <span class="flex-1 text-sm truncate">
                        {asset_type_label(item.asset_type)}
                      </span>
                      <span class="text-sm font-medium">{format_currency(item.total)}</span>
                      <span class="text-xs opacity-50">
                        {percentage(item.total, @summary.market_value)}%
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
            <%= if has_aportes?(@activity) do %>
              <div class="card bg-base-200 p-4 sm:p-6">
                <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
                  Aportes
                </h3>
                <div
                  id="inv-aportes-chart"
                  phx-hook="DailyChart"
                  data-daily={aportes_chart_data(@activity, @view_mode, @selected_month)}
                  data-bar-fill="fill-info"
                >
                  <div class="space-y-1">
                    <div
                      :for={a <- @activity}
                      :if={Decimal.compare(a.aportes, 0) == :gt}
                      class="flex items-center gap-2"
                    >
                      <span class="text-xs w-10 opacity-60">
                        {format_activity_label(a.key, @view_mode, @selected_month)}
                      </span>
                      <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
                        <div
                          class="bg-info h-full rounded-full transition-all"
                          style={"width: #{activity_bar_width(a.aportes, @activity, :aportes)}%"}
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
          <div :if={active_holdings(@summary.holdings) != []} class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6">
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
                  <tr :for={h <- Enum.take(active_holdings(@summary.holdings), 30)} class="hover">
                    <td>
                      <div class="flex items-center gap-2">
                        <div :if={h.institution_logo || h.logo_url} class="w-6 h-6 rounded-full overflow-hidden bg-base-300 shrink-0">
                          <img src={h.institution_logo || h.logo_url} alt=""/>
                        </div>
                        <div class="flex flex-col">
                          <span class="font-medium text-sm">{h.ticker || "—"}</span>
                          <span class="text-xs opacity-50 truncate max-w-[120px] sm:max-w-xs">{h.name}</span>
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

          <%!-- Maiores Pagadores de Proventos (period-filtered) --%>
          <div :if={@period_proventos_by_asset != []} class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6">
            <h3 class="font-semibold text-sm sm:text-base mb-3 sm:mb-4">
              Proventos e Resultados por Ativo
              <span class="text-xs font-normal opacity-50 ml-2">{period_label(@view_mode, @selected_year, @selected_month)}</span>
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
                  <tr :for={r <- Enum.take(@period_proventos_by_asset, 20)} class="hover">
                    <td>
                      <div class="flex items-center gap-2">
                        <div :if={r.institution_logo} class="w-6 h-6 rounded-full overflow-hidden bg-base-300 shrink-0">
                          <img src={r.institution_logo} alt="" />
                        </div>
                        <div class="flex flex-col">
                          <span class="font-medium text-sm">{r.ticker || r.name}</span>
                          <span :if={r.ticker && r.ticker != r.name} class="text-xs opacity-50 truncate max-w-xs">{r.name}</span>
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
      </div>
    </Layouts.app>
    """
  end

  # --- Helpers ---

  defp active_holdings(holdings) do
    holdings
    |> Enum.filter(& &1.is_active)
  end

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

  defp gain_loss_class(amount) do
    case Decimal.compare(amount, 0) do
      :gt -> "text-success"
      :lt -> "text-error"
      _ -> "opacity-50"
    end
  end

  defp period_label("total", _year, _month), do: "acumulado"
  defp period_label("year", year, _month), do: "em #{year}"

  defp period_label("month", year, month) do
    "em #{Banking.month_name_short(month)}/#{year}"
  end


  defp format_currency(amount) do
    "R$ #{format_br_number(amount)}"
  end

  defp format_currency_signed(amount) do
    case Decimal.compare(amount, 0) do
      :lt -> "- R$ #{format_br_number(Decimal.abs(amount))}"
      _ -> "+ R$ #{format_br_number(amount)}"
    end
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

    "#{int_formatted},#{dec_part}"
  end

  defp format_quantity(qty) do
    float = Decimal.to_float(qty)

    if float == Float.round(float),
      do: "#{trunc(float)}",
      else: Decimal.to_string(Decimal.round(qty, 4))
  end

  defp format_pct(pct) do
    val = Decimal.round(pct, 2) |> Decimal.to_string()
    sign = if Decimal.compare(pct, 0) != :lt, do: "+", else: ""
    "#{sign}#{val}%"
  end

  defp percentage(part, total) do
    case Decimal.compare(total, 0) do
      :gt ->
        part |> Decimal.div(total) |> Decimal.mult(100) |> Decimal.round(1) |> Decimal.to_string()

      _ ->
        "0"
    end
  end

  defp months_for_year(available_months, year) do
    available_months
    |> Enum.filter(fn {y, _m} -> y == year end)
    |> Enum.map(fn {_y, m} -> m end)
    |> Enum.sort()
  end

  defp format_activity_label(key, "total", _month), do: to_string(key)
  defp format_activity_label(key, "year", _month), do: Banking.month_name_short(key)

  defp format_activity_label(day, "month", month) do
    dd = String.pad_leading(to_string(day), 2, "0")
    mm = String.pad_leading(to_string(month), 2, "0")
    "#{dd}/#{mm}"
  end

  defp asset_type_label("acao"), do: "Ações"
  defp asset_type_label("fii"), do: "FII"
  defp asset_type_label("etf"), do: "ETF"
  defp asset_type_label("bdr"), do: "BDR"
  defp asset_type_label("renda_fixa"), do: "Renda Fixa"
  defp asset_type_label("tesouro"), do: "Tesouro"
  defp asset_type_label("cripto"), do: "Cripto"
  defp asset_type_label("fundo"), do: "Fundo"
  defp asset_type_label("nota_fiscal"), do: "Nota Fiscal"
  defp asset_type_label("debenture"), do: "Debênture"
  defp asset_type_label("precatorio"), do: "Precatório"
  defp asset_type_label("recebiveis"), do: "Receb. Judiciais"
  defp asset_type_label("cri"), do: "CRI"
  defp asset_type_label("cra"), do: "CRA"
  defp asset_type_label("op_estruturada"), do: "Op. Estruturada"
  defp asset_type_label("outro"), do: "Outro"
  defp asset_type_label(_), do: "—"

  @asset_colors %{
    "acao" => "#3B82F6",
    "fii" => "#8B5CF6",
    "etf" => "#06B6D4",
    "bdr" => "#F59E0B",
    "renda_fixa" => "#10B981",
    "tesouro" => "#EF4444",
    "cripto" => "#F97316",
    "fundo" => "#EC4899",
    "nota_fiscal" => "#14B8A6",
    "debenture" => "#6366F1",
    "precatorio" => "#D946EF",
    "recebiveis" => "#0EA5E9",
    "cri" => "#84CC16",
    "cra" => "#22D3EE",
    "op_estruturada" => "#A855F7",
    "outro" => "#9CA3AF"
  }

  @individual_colors [
    "#8B5CF6", "#3B82F6", "#06B6D4", "#10B981", "#F59E0B",
    "#EF4444", "#EC4899", "#F97316", "#6366F1", "#14B8A6"
  ]

  defp asset_type_color(type), do: Map.get(@asset_colors, type, "#9CA3AF")

  defp individual_color(index),
    do: Enum.at(@individual_colors, rem(index, length(@individual_colors)))

  defp asset_type_badge("acao"), do: "badge-info"
  defp asset_type_badge("fii"), do: "badge-secondary"
  defp asset_type_badge("etf"), do: "badge-accent"
  defp asset_type_badge("bdr"), do: "badge-warning"
  defp asset_type_badge("renda_fixa"), do: "badge-success"
  defp asset_type_badge("tesouro"), do: "badge-error"
  defp asset_type_badge("cripto"), do: "badge-warning"
  defp asset_type_badge("fundo"), do: "badge-primary"
  defp asset_type_badge("nota_fiscal"), do: "badge-accent"
  defp asset_type_badge("debenture"), do: "badge-info"
  defp asset_type_badge("precatorio"), do: "badge-secondary"
  defp asset_type_badge("recebiveis"), do: "badge-primary"
  defp asset_type_badge("cri"), do: "badge-success"
  defp asset_type_badge("cra"), do: "badge-success"
  defp asset_type_badge("op_estruturada"), do: "badge-secondary"
  defp asset_type_badge(_), do: "badge-ghost"

  # --- Chart Data ---

  defp proventos_chart_data(activity, view_mode, month) do
    activity
    |> Enum.map(fn a ->
      %{date: format_activity_label(a.key, view_mode, month), value: Decimal.to_float(a.proventos), url: ""}
    end)
    |> Jason.encode!()
  end

  defp aportes_chart_data(activity, view_mode, month) do
    activity
    |> Enum.map(fn a ->
      %{date: format_activity_label(a.key, view_mode, month), value: Decimal.to_float(a.aportes), url: ""}
    end)
    |> Jason.encode!()
  end

  defp individual_asset_chart_data(by_asset_individual, market_value) do
    total = Decimal.to_float(market_value)

    by_asset_individual
    |> Enum.with_index()
    |> Enum.map(fn {h, idx} ->
      %{
        name: h.ticker || h.name,
        value: Decimal.to_float(h.current_value),
        color: individual_color(idx),
        url: ""
      }
    end)
    |> then(fn data -> if total > 0, do: data, else: [] end)
    |> Jason.encode!()
  end

  defp asset_type_chart_data(by_asset_type, market_value) do
    total = Decimal.to_float(market_value)

    by_asset_type
    |> Enum.map(fn item ->
      %{
        name: asset_type_label(item.asset_type),
        value: Decimal.to_float(item.total),
        color: asset_type_color(item.asset_type),
        url: ""
      }
    end)
    |> then(fn data -> if total > 0, do: data, else: [] end)
    |> Jason.encode!()
  end
end
