defmodule GranaWeb.TransactionsLive do
  use GranaWeb, :live_view

  alias Grana.Banking
  alias Grana.Investments
  alias Grana.Investments.Constants

  @per_page 50
  @sort_fields ~w(date description source kind amount)
  @sort_dirs ~w(asc desc)
  @dividend_ops Constants.dividend_ops()
  @income_ops ~w(venda) ++ @dividend_ops

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    socket =
      socket
      |> assign(:page_title, "Transações")
      |> assign(:categories, Banking.ensure_default_categories(user_id))
      |> assign(:banks, Banking.available_banks(user_id))
      |> assign(:inv_institutions, Investments.available_institutions(user_id))
      |> assign(:inv_asset_types, Investments.available_asset_types(user_id))
      |> assign(:inv_operations, Investments.available_operations(user_id))
      |> assign(:expanded_ids, MapSet.new())
      |> assign(:selected_ids, MapSet.new())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user_id = socket.assigns.current_scope.user.id
    filters = build_filters(params)
    page = parse_int(params["page"], 1)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:page, page)
      |> load_transactions(user_id)

    {:noreply, socket}
  end

  # ── Events ──

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    source = normalize_source(tab)
    filters = %{socket.assigns.filters | source: source}
    {:noreply, push_patch(socket, to: transactions_url(filters))}
  end

  def handle_event("apply_filters", params, socket) do
    next =
      params
      |> build_filters()
      |> Map.put(:sort_by, socket.assigns.filters.sort_by)
      |> Map.put(:sort_dir, socket.assigns.filters.sort_dir)

    {:noreply, push_patch(socket, to: transactions_url(next))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/transactions")}
  end

  def handle_event("clear_statement", _params, socket) do
    filters = %{socket.assigns.filters | statement_id: nil, statement_source: nil}
    {:noreply, push_patch(socket, to: transactions_url(filters))}
  end

  def handle_event("search", %{"search" => term}, socket) do
    filters = %{socket.assigns.filters | search: term}
    {:noreply, push_patch(socket, to: transactions_url(filters))}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    filters = %{socket.assigns.filters | filter: filter}
    {:noreply, push_patch(socket, to: transactions_url(filters))}
  end

  def handle_event("toggle-description", %{"id" => id}, socket) do
    id = parse_int(id, -1)
    expanded = socket.assigns.expanded_ids

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, :expanded_ids, expanded)}
  end

  def handle_event("save-category", %{"txn_id" => id, "category_id" => category_id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    cat_id = parse_int(category_id, -1)

    if Banking.category_belongs_to_user?(cat_id, user_id) do
      transaction = Banking.get_transaction!(parse_int(id, -1), user_id)
      {:ok, _} = Banking.update_transaction(transaction, %{category_id: cat_id})

      description = transaction.description |> String.downcase() |> String.trim()
      Banking.create_category_rule(%{pattern: description, user_id: user_id, category_id: cat_id})

      socket =
        socket
        |> put_flash(:info, "Categoria atualizada e regra salva")
        |> push_patch(to: transactions_url(socket.assigns.filters, socket.assigns.page))

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Categoria inválida.")}
    end
  end

  def handle_event("save-recurring", %{"txn_id" => id, "mode" => mode}, socket) do
    user_id = socket.assigns.current_scope.user.id
    txn_id = parse_int(id, -1)

    case Banking.set_transaction_recurring_mode(user_id, txn_id, mode) do
      {:ok, _rule} ->
        socket =
          socket
          |> put_flash(:info, recurring_flash(mode))
          |> push_patch(to: transactions_url(socket.assigns.filters, socket.assigns.page))

        {:noreply, socket}

      {:error, :not_recurring_expense} ->
        {:noreply, put_flash(socket, :error, "Só despesas bancárias podem virar fixas.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar a recorrência.")}
    end
  end

  def handle_event("toggle-internal", %{"id" => id, "internal" => internal}, socket) do
    user_id = socket.assigns.current_scope.user.id
    internal? = internal == "true"

    {:ok, scope} = Banking.set_transaction_internal(user_id, parse_int(id, -1), internal?)

    base = if internal?, do: "Marcada como transferência interna", else: "Marcada como externa"
    msg = if scope == :rule, do: base <> " (regra salva pra essa contraparte)", else: base

    socket =
      socket
      |> put_flash(:info, msg)
      |> push_patch(to: transactions_url(socket.assigns.filters, socket.assigns.page))

    {:noreply, socket}
  end

  def handle_event("toggle-select", %{"id" => id}, socket) do
    id = parse_int(id, -1)
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("toggle-select-all", _params, socket) do
    %{transactions: rows, selected_ids: selected} = socket.assigns
    page_ids = rows |> Enum.filter(& &1.selectable?) |> MapSet.new(& &1.raw_id)

    selected =
      if MapSet.subset?(page_ids, selected),
        do: MapSet.difference(selected, page_ids),
        else: MapSet.union(selected, page_ids)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("bulk-apply", params, socket) do
    user_id = socket.assigns.current_scope.user.id
    ids = MapSet.to_list(socket.assigns.selected_ids)
    cat_id = parse_int(params["category_id"] || "", -1)
    mode = params["mode"]

    cond do
      ids == [] ->
        {:noreply, put_flash(socket, :error, "Nenhuma transação bancária selecionada.")}

      cat_id > 0 and not Banking.category_belongs_to_user?(cat_id, user_id) ->
        {:noreply, put_flash(socket, :error, "Categoria inválida.")}

      cat_id <= 0 and mode not in ["fixed", "variable"] ->
        {:noreply,
         put_flash(socket, :error, "Escolha uma categoria ou recorrência para aplicar.")}

      true ->
        msgs =
          []
          |> maybe_bulk_category(ids, cat_id, user_id)
          |> maybe_bulk_recurring(ids, mode, user_id)

        socket =
          socket
          |> assign(:selected_ids, MapSet.new())
          |> put_flash(:info, msgs |> Enum.reverse() |> Enum.join(" · "))
          |> push_patch(to: transactions_url(socket.assigns.filters, socket.assigns.page))

        {:noreply, socket}
    end
  end

  def handle_event("clear-selection", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  # ── Loading ──

  defp load_transactions(socket, user_id) do
    %{filters: filters, page: page} = socket.assigns

    banking_transactions =
      if include_banking?(filters),
        do: Banking.list_transactions(user_id, banking_opts(filters)),
        else: []

    investment_transactions =
      if include_investments?(filters),
        do: Investments.list_transactions(user_id, investment_opts(filters)),
        else: []

    all_rows =
      banking_transactions
      |> Enum.map(&banking_row/1)
      |> Kernel.++(Enum.map(investment_transactions, &investment_row/1))
      |> sort_rows(filters.sort_by, filters.sort_dir)

    total = length(all_rows)
    total_pages = max(1, ceil(total / @per_page))
    page = min(page, total_pages)
    page_rows = Enum.slice(all_rows, (page - 1) * @per_page, @per_page)
    visible_banking = page_rows |> Enum.filter(&(&1.source == :banking)) |> Enum.map(& &1.raw)

    socket
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:total, total)
    |> assign(:banking_total, length(banking_transactions))
    |> assign(:investment_total, length(investment_transactions))
    |> assign(:transactions, page_rows)
    |> assign(:summary, unified_summary(all_rows))
    |> assign(:recurring_statuses, Banking.recurring_statuses(user_id, visible_banking))
    |> assign(:statement_info, statement_info(filters, user_id))
    |> assign(:selected_ids, MapSet.new())
  end

  defp banking_opts(filters) do
    []
    |> maybe_add_opt(:search, filters.search)
    |> maybe_add_opt(:bank, origin_bank(filters.origin))
    |> maybe_add_opt(:statement_type, kind_statement_type(filters.kind))
    |> maybe_add_opt(:type, banking_type(filters.movement))
    |> maybe_add_opt(:category_id, kind_category_id(filters.kind))
    |> maybe_add_opt(:date_from, parse_date(filters.date_from))
    |> maybe_add_opt(:date_to, parse_date(filters.date_to))
    |> maybe_add_opt(:amount_min, parse_decimal(filters.amount_min))
    |> maybe_add_opt(:amount_max, parse_decimal(filters.amount_max))
    |> maybe_add_opt(:internal, filters.internal)
    |> maybe_add_opt(:bank_statement_id, statement_id(filters, "banking"))
    |> maybe_uncategorized(filters)
  end

  defp investment_opts(filters) do
    []
    |> maybe_add_opt(:search, filters.search)
    |> maybe_add_opt(:operation, investment_operation(filters.movement))
    |> maybe_add_opt(:asset_type, kind_asset_type(filters.kind))
    |> maybe_add_opt(:institution_id, origin_institution_id(filters.origin))
    |> maybe_add_opt(:date_from, parse_date(filters.date_from))
    |> maybe_add_opt(:date_to, parse_date(filters.date_to))
    |> maybe_add_opt(:amount_min, parse_decimal(filters.amount_min))
    |> maybe_add_opt(:amount_max, parse_decimal(filters.amount_max))
    |> maybe_add_opt(:statement_id, statement_id(filters, "investments"))
  end

  defp maybe_uncategorized(opts, %{filter: "uncategorized"}),
    do: Keyword.put(opts, :uncategorized, true)

  defp maybe_uncategorized(opts, _filters), do: opts

  defp include_banking?(%{source: "investments"}), do: false

  defp include_banking?(filters) do
    not origin_investment?(filters.origin) and
      not kind_investment?(filters.kind) and
      not movement_investment_only?(filters.movement) and
      not statement_for?(filters, "investments")
  end

  defp include_investments?(%{source: "banking"}), do: false

  defp include_investments?(%{source: "investments"} = filters) do
    not origin_banking?(filters.origin) and
      not kind_banking?(filters.kind) and
      not movement_banking_only?(filters.movement) and
      not statement_for?(filters, "banking")
  end

  defp include_investments?(filters) do
    filters.internal == "all" and
      filters.filter == "all" and
      not origin_banking?(filters.origin) and
      not kind_banking?(filters.kind) and
      not movement_banking_only?(filters.movement) and
      not statement_for?(filters, "banking")
  end

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-4 sm:mb-8 text-center sm:text-left">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Transações</h1>
          <p class="text-xs sm:text-sm opacity-60 mt-1">
            Visualize e gerencie todas as suas transações em uma lista única
          </p>
        </div>

        <div :if={@statement_info} class="mb-4">
          <div class="badge badge-lg badge-outline gap-2">
            <img
              :if={@statement_info.logo}
              src={@statement_info.logo}
              alt=""
              class="w-4 h-4 rounded-full"
            />
            <.icon :if={!@statement_info.logo} name={@statement_info.icon} class="size-4" />
            {@statement_info.label}: {@statement_info.filename}
            <button phx-click="clear_statement" class="btn btn-ghost btn-xs btn-circle">
              <.icon name="hero-x-mark" class="size-3" />
            </button>
          </div>
        </div>

        <div class="card bg-base-200 p-4 mb-6">
          <form id="transactions-filters" phx-change="apply_filters" phx-submit="apply_filters">
            <input
              :if={@filters.statement_id}
              type="hidden"
              name="statement_id"
              value={@filters.statement_id}
            />
            <input
              :if={@filters.statement_source}
              type="hidden"
              name="statement_source"
              value={@filters.statement_source}
            />

            <div class="transactions-filter-grid">
              <div class="transactions-filter-search">
                <input
                  type="search"
                  name="search"
                  value={@filters.search}
                  placeholder="Buscar transação, categoria ou ativo..."
                  class="input input-bordered input-sm w-full"
                  phx-debounce="300"
                />
              </div>

              <div class="transactions-filter-source">
                <select name="source" class="select select-bordered select-sm w-full">
                  <option value="all" selected={@filters.source == "all"}>Todas as fontes</option>
                  <option value="banking" selected={@filters.source == "banking"}>Bancário</option>
                  <option value="investments" selected={@filters.source == "investments"}>
                    Investimentos
                  </option>
                </select>
              </div>

              <div class="transactions-filter-movement">
                <select name="movement" class="select select-bordered select-sm w-full">
                  <option value="all" selected={@filters.movement == "all"}>Todos movimentos</option>
                  <optgroup label="Bancário">
                    <option value="expense" selected={@filters.movement == "expense"}>
                      Despesas
                    </option>
                    <option value="income" selected={@filters.movement == "income"}>Receitas</option>
                    <option value="bank_investment" selected={@filters.movement == "bank_investment"}>
                      Investimentos
                    </option>
                  </optgroup>
                  <optgroup label="Investimentos">
                    <option value="purchase" selected={@filters.movement == "purchase"}>
                      Compras
                    </option>
                    <option value="sale" selected={@filters.movement == "sale"}>Vendas</option>
                    <option value="dividend" selected={@filters.movement == "dividend"}>
                      Proventos
                    </option>
                    <option value="fee" selected={@filters.movement == "fee"}>Taxas</option>
                  </optgroup>
                </select>
              </div>

              <div class="transactions-filter-origin">
                <label class="text-xs opacity-50 mb-1 block">Origem</label>
                <select name="origin" class="select select-bordered select-sm w-full">
                  <option value="all" selected={@filters.origin == "all"}>Todas origens</option>
                  <optgroup :if={@banks != []} label="Bancos">
                    <option
                      :for={bank <- @banks}
                      value={"bank:#{bank}"}
                      selected={@filters.origin == "bank:#{bank}"}
                    >
                      {String.capitalize(bank)}
                    </option>
                  </optgroup>
                  <optgroup :if={@inv_institutions != []} label="Instituições">
                    <option
                      :for={inst <- @inv_institutions}
                      value={"institution:#{inst.id}"}
                      selected={@filters.origin == "institution:#{inst.id}"}
                    >
                      {inst.name}
                    </option>
                  </optgroup>
                </select>
              </div>

              <div class="transactions-filter-kind">
                <label class="text-xs opacity-50 mb-1 block">Classificação</label>
                <select name="kind" class="select select-bordered select-sm w-full">
                  <option value="all" selected={@filters.kind == "all"}>Todos os tipos</option>
                  <optgroup label="Bancário">
                    <option value="statement:extrato" selected={@filters.kind == "statement:extrato"}>
                      Extrato
                    </option>
                    <option value="statement:fatura" selected={@filters.kind == "statement:fatura"}>
                      Fatura
                    </option>
                    <option
                      :for={cat <- @categories}
                      value={"category:#{cat.id}"}
                      selected={@filters.kind == "category:#{cat.id}"}
                    >
                      {cat.name}
                    </option>
                  </optgroup>
                  <optgroup :if={@inv_asset_types != []} label="Investimentos">
                    <option
                      :for={asset_type <- @inv_asset_types}
                      value={"asset:#{asset_type}"}
                      selected={@filters.kind == "asset:#{asset_type}"}
                    >
                      {asset_type_label(asset_type)}
                    </option>
                  </optgroup>
                </select>
              </div>

              <div class="transactions-filter-date-from">
                <label class="text-xs opacity-50 mb-1 block">Data início</label>
                <input
                  type="date"
                  name="date_from"
                  value={@filters.date_from}
                  class="input input-bordered input-sm w-full"
                />
              </div>

              <div class="transactions-filter-date-to">
                <label class="text-xs opacity-50 mb-1 block">Data fim</label>
                <input
                  type="date"
                  name="date_to"
                  value={@filters.date_to}
                  class="input input-bordered input-sm w-full"
                />
              </div>

              <div class="transactions-filter-min">
                <label class="text-xs opacity-50 mb-1 block">Valor mínimo</label>
                <input
                  type="number"
                  name="amount_min"
                  value={@filters.amount_min}
                  step="0.01"
                  placeholder="0,00"
                  class="input input-bordered input-sm w-full"
                />
              </div>

              <div class="transactions-filter-max">
                <label class="text-xs opacity-50 mb-1 block">Valor máximo</label>
                <input
                  type="number"
                  name="amount_max"
                  value={@filters.amount_max}
                  step="0.01"
                  placeholder="0,00"
                  class="input input-bordered input-sm w-full"
                />
              </div>

              <div class="transactions-filter-internal">
                <label class="text-xs opacity-50 mb-1 block">Transferências internas</label>
                <select name="internal" class="select select-bordered select-sm w-full">
                  <option value="all" selected={@filters.internal == "all"}>Todas</option>
                  <option value="hide" selected={@filters.internal == "hide"}>
                    Ocultar internas
                  </option>
                  <option value="only" selected={@filters.internal == "only"}>Apenas internas</option>
                </select>
              </div>

              <div class="transactions-filter-clear flex items-end justify-end">
                <button type="button" phx-click="clear_filters" class="btn btn-error btn-xs">
                  Limpar filtros
                </button>
              </div>
            </div>
          </form>
        </div>

        <div class="flex items-center gap-4 text-sm mb-3 flex-wrap">
          <span :if={@total == 0} class="opacity-60">Nenhuma transação</span>
          <span :if={@total > 1} class="opacity-60">{@total} transações</span>
          <span :if={@total == 1} class="opacity-60">{@total} transação</span>
          <span :if={@banking_total > 0} class="opacity-50">
            {@banking_total} bancária(s)
          </span>
          <span :if={@investment_total > 0} class="opacity-50">
            {@investment_total} investimento(s)
          </span>
          <span
            :if={Decimal.compare(@summary.bank_expenses, 0) == :gt}
            class="text-error font-medium"
          >
            Despesas: R$ {format_br_number(@summary.bank_expenses)}
          </span>
          <span
            :if={Decimal.compare(@summary.bank_income, 0) == :gt}
            class="text-success font-medium"
          >
            Receitas: R$ {format_br_number(@summary.bank_income)}
          </span>
          <span
            :if={Decimal.compare(@summary.inv_dividends, 0) == :gt}
            class="text-success font-medium"
          >
            Proventos: R$ {format_br_number(@summary.inv_dividends)}
          </span>
          <span
            :if={Decimal.compare(@summary.inv_fees, 0) == :gt}
            class="text-error font-medium"
          >
            Taxas: R$ {format_br_number(@summary.inv_fees)}
          </span>

          <div :if={@total > 0} class="flex gap-2 ml-auto">
            <a
              :if={@banking_total > 0}
              href={"/transactions/export?#{banking_export_query(@filters)}"}
              class="btn btn-sm gap-1"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" />
              {if @investment_total > 0, do: "Exportar bancário", else: "Exportar CSV"}
            </a>
            <a
              :if={@investment_total > 0}
              href={"/transactions/export/investments?#{investment_export_query(@filters)}"}
              class="btn btn-sm gap-1"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" />
              {if @banking_total > 0, do: "Exportar investimentos", else: "Exportar CSV"}
            </a>
          </div>
        </div>

        <div
          :if={MapSet.size(@selected_ids) > 0}
          class="flex items-center gap-x-4 gap-y-2 flex-wrap bg-primary/10 border border-primary/20 rounded-lg px-4 py-3 mb-4"
        >
          <span class="text-sm font-medium whitespace-nowrap">
            {MapSet.size(@selected_ids)} bancária(s) selecionada(s)
          </span>
          <form phx-submit="bulk-apply" class="flex items-end gap-x-3 gap-y-2 flex-wrap">
            <label class="flex flex-col gap-1">
              <span class="text-xs opacity-60">Categoria</span>
              <select name="category_id" class="select select-bordered select-sm">
                <option :for={cat <- @categories} value={cat.id}>{cat.name}</option>
              </select>
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs opacity-60">Recorrência</span>
              <select name="mode" class="select select-bordered select-sm">
                <option value="fixed">Fixa</option>
                <option value="variable">Variável</option>
              </select>
            </label>
            <button type="submit" class="btn btn-primary btn-sm">Aplicar</button>
          </form>
          <button phx-click="clear-selection" class="btn btn-ghost btn-sm ml-auto">Limpar</button>
        </div>

        <div :if={@transactions == []} class="text-center py-16">
          <.icon name="hero-document-magnifying-glass" class="size-16 mx-auto mb-4 opacity-20" />
          <h2 class="text-xl font-semibold mb-2">Nenhuma transação encontrada</h2>
          <p class="opacity-60 mb-6">Importe dados bancários ou de investimento para começar</p>
          <.link navigate={~p"/upload"} class="btn btn-primary">
            <.icon name="hero-cloud-arrow-up" class="size-5" /> Upload
          </.link>
        </div>

        <div
          :if={@transactions != []}
          class="transactions-table-shell card bg-base-200 overflow-x-auto"
        >
          <table id="transactions-table" class="table">
            <thead>
              <tr>
                <th class="w-8">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs"
                    checked={all_selected?(@transactions, @selected_ids)}
                    phx-click="toggle-select-all"
                  />
                </th>
                <.sortable_header filters={@filters} field="date" label="Data" />
                <.sortable_header filters={@filters} field="description" label="Transação" />
                <.sortable_header filters={@filters} field="source" label="Origem" />
                <.sortable_header
                  filters={@filters}
                  field="kind"
                  label="Classificação"
                  class="text-center"
                />
                <th class="text-center">Recorrência</th>
                <.sortable_header filters={@filters} field="amount" label="Valor" class="text-right" />
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @transactions}
                id={"transaction-#{row.id}"}
                class={[
                  "hover",
                  row.source == :banking && row.raw.is_internal_transfer && "opacity-50"
                ]}
              >
                <td>
                  <input
                    :if={row.selectable?}
                    type="checkbox"
                    class="checkbox checkbox-xs"
                    checked={MapSet.member?(@selected_ids, row.raw_id)}
                    phx-click="toggle-select"
                    phx-value-id={row.raw_id}
                  />
                  <span :if={!row.selectable?} class="text-xs opacity-30">—</span>
                </td>
                <td class="text-sm whitespace-nowrap">{Calendar.strftime(row.date, "%d/%m/%Y")}</td>
                <td class="text-sm max-w-xs">{render_title_cell(assigns, row)}</td>
                <td>{render_origin_cell(row)}</td>
                <td class="text-center">{render_kind_cell(assigns, row)}</td>
                <td class="text-center">{render_recurring_column(assigns, row)}</td>
                <td class={["text-right text-sm font-medium whitespace-nowrap", amount_class(row)]}>
                  {format_row_amount(row)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@total_pages > 1} class="flex justify-center gap-2 mt-6">
          <.link
            :if={@page > 1}
            patch={transactions_url(@filters, @page - 1)}
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-chevron-left" class="size-4" />
          </.link>
          <span :for={p <- page_range(@page, @total_pages)}>
            <.link
              :if={is_integer(p)}
              patch={transactions_url(@filters, p)}
              class={["btn btn-sm", (p == @page && "btn-primary") || "btn-ghost"]}
            >
              {p}
            </.link>
            <span :if={p == :dots} class="px-2 opacity-40">...</span>
          </span>
          <.link
            :if={@page < @total_pages}
            patch={transactions_url(@filters, @page + 1)}
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-chevron-right" class="size-4" />
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Row rendering ──

  defp render_title_cell(assigns, %{source: :banking} = row) do
    assigns = assign(assigns, :row, row)

    ~H"""
    <div class="flex items-center gap-2">
      <span
        class={[
          "cursor-pointer hover:opacity-70",
          !MapSet.member?(@expanded_ids, @row.raw_id) && "truncate"
        ]}
        phx-click="toggle-description"
        phx-value-id={@row.raw_id}
        title={
          if !MapSet.member?(@expanded_ids, @row.raw_id),
            do: @row.raw.original_description || @row.raw.description
        }
      >
        {@row.raw.description}
      </span>
      <button
        :if={@row.raw.is_internal_transfer}
        type="button"
        phx-click="toggle-internal"
        phx-value-id={@row.raw_id}
        phx-value-internal="false"
        class="badge badge-xs badge-ghost shrink-0 opacity-60 cursor-pointer hover:opacity-100"
        title="Transferência interna (fora dos totais). Clique para marcar como externa."
      >
        interna
      </button>
      <button
        :if={not @row.raw.is_internal_transfer and transfer_like?(@row.raw.description)}
        type="button"
        phx-click="toggle-internal"
        phx-value-id={@row.raw_id}
        phx-value-internal="true"
        class="badge badge-xs badge-ghost shrink-0 opacity-30 cursor-pointer hover:opacity-100"
        title="Marcar como transferência interna (entre suas contas)"
      >
        marcar interna
      </button>
    </div>
    """
  end

  defp render_title_cell(assigns, %{source: :investment} = row) do
    assigns = assign(assigns, :row, row)

    ~H"""
    <div>
      <span class="font-medium">{@row.raw.asset_ticker || @row.raw.asset_name}</span>
      <span
        :if={@row.raw.asset_ticker && @row.raw.asset_name != @row.raw.asset_ticker}
        class="text-xs opacity-50 block truncate max-w-64"
        title={@row.raw.asset_name}
      >
        {@row.raw.asset_name}
      </span>
    </div>
    """
  end

  defp render_origin_cell(%{source: :banking, raw: txn}) do
    assigns = %{txn: txn}

    ~H"""
    <span :if={@txn.bank_statement} class="badge badge-outline gap-1 h-auto whitespace-nowrap">
      <div class="w-4 h-4 rounded-full overflow-hidden bg-base-300 shrink-0">
        <img src={bank_logo(@txn.bank_statement.bank)} alt="" />
      </div>
      {String.capitalize(@txn.bank_statement.bank)}
      <span class="opacity-50">({statement_type_label(@txn.bank_statement.statement_type)})</span>
    </span>
    """
  end

  defp render_origin_cell(%{source: :investment, raw: txn}) do
    assigns = %{txn: txn}

    ~H"""
    <span :if={@txn.institution} class="badge badge-outline gap-1 h-auto whitespace-nowrap">
      <div class="w-4 h-4 rounded-full overflow-hidden bg-base-300 shrink-0">
        <img
          src={Grana.Investments.Institution.logo_url(@txn.institution) || ~p"/images/logo-32.png"}
          alt=""
        />
      </div>
      {@txn.institution.name}
    </span>
    """
  end

  defp render_kind_cell(assigns, %{source: :banking} = row) do
    assigns = assign(assigns, :row, row)

    ~H"""
    <form
      id={"transaction-category-form-#{@row.raw_id}"}
      phx-change="save-category"
      class="flex items-center justify-center gap-2"
    >
      <input type="hidden" name="txn_id" value={@row.raw_id} />
      <span
        class={["size-3 rounded-full shrink-0", !@row.raw.category && "bg-base-content/20"]}
        style={@row.raw.category && "background-color: #{@row.raw.category.color}"}
      >
      </span>
      <select
        name="category_id"
        aria-label="Categoria"
        title="Alterar categoria"
        class={[
          "select select-bordered select-sm w-full max-w-44",
          !@row.raw.category && "select-warning"
        ]}
      >
        <option
          :for={cat <- @categories}
          value={cat.id}
          selected={@row.raw.category_id == cat.id}
        >
          {cat.name}
        </option>
      </select>
    </form>
    """
  end

  defp render_kind_cell(assigns, %{source: :investment} = row) do
    assigns = assign(assigns, :row, row)

    ~H"""
    <div class="flex items-center justify-center gap-2">
      <span class="size-3 rounded-full shrink-0 bg-base-content/20"></span>
      <select
        class="select select-bordered select-sm w-full max-w-44"
        aria-label="Tipo de ativo"
        disabled
      >
        <option selected>{asset_type_label(@row.raw.asset_type)}</option>
      </select>
    </div>
    """
  end

  defp render_recurring_column(assigns, %{source: :banking} = row) do
    render_recurring_cell(assigns, row.raw)
  end

  defp render_recurring_column(assigns, %{source: :investment}) do
    ~H"""
    <span class="inline-flex w-full justify-center text-xs opacity-30">—</span>
    """
  end

  defp render_recurring_cell(assigns, txn) do
    assigns =
      assigns
      |> assign(:txn, txn)
      |> assign(:recurring, recurring_status(assigns.recurring_statuses, txn.id))

    ~H"""
    <div class="flex min-w-28 justify-center">
      <form
        :if={@recurring.editable}
        id={"transaction-recurring-form-#{@txn.id}"}
        phx-change="save-recurring"
        class="flex w-full justify-center"
      >
        <input type="hidden" name="txn_id" value={@txn.id} />
        <select
          name="mode"
          aria-label="Recorrência da despesa"
          title="Alterar recorrência"
          class="select select-bordered select-sm w-full"
        >
          <option value="fixed" selected={@recurring.status == "fixed"}>Fixa</option>
          <option value="variable" selected={@recurring.status == "variable"}>Variável</option>
        </select>
      </form>

      <span :if={!@recurring.editable} class="inline-flex w-full justify-center text-xs opacity-30">
        —
      </span>
    </div>
    """
  end

  defp sortable_header(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <th class={@class}>
      <.link
        patch={sort_url(@filters, @field)}
        class={[
          "inline-flex items-center gap-1 rounded-md transition hover:text-primary",
          @class == "text-right" && "justify-end w-full",
          @class == "text-center" && "justify-center w-full"
        ]}
      >
        <span>{@label}</span>
        <.icon
          :if={@filters.sort_by == @field}
          name={sort_icon(@filters.sort_dir)}
          class="size-3"
        />
      </.link>
    </th>
    """
  end

  # ── Filters and URLs ──

  defp build_filters(params) do
    tab_source = tab_to_source(params["tab"])
    source = normalize_source(params["source"] || tab_source || "all")
    statement_id = params["statement_id"]

    statement_source =
      if statement_id in [nil, ""] do
        nil
      else
        normalize_statement_source(params["statement_source"] || tab_source || source)
      end

    %{
      source: source,
      search: params["search"] || "",
      origin: normalize_origin(params),
      kind: normalize_kind(params),
      movement: normalize_movement(params),
      date_from: params["date_from"] || "",
      date_to: params["date_to"] || "",
      amount_min: params["amount_min"] || "",
      amount_max: params["amount_max"] || "",
      internal: params["internal"] || "all",
      filter: params["filter"] || "all",
      statement_id: statement_id,
      statement_source: statement_source,
      sort_by: normalize_sort_by(params["sort_by"]),
      sort_dir: normalize_sort_dir(params["sort_dir"])
    }
  end

  defp normalize_source(source) when source in ["all", "banking", "investments"], do: source
  defp normalize_source(_source), do: "all"

  defp normalize_statement_source("investments"), do: "investments"
  defp normalize_statement_source(_source), do: "banking"

  defp tab_to_source("banking"), do: "banking"
  defp tab_to_source("investments"), do: "investments"
  defp tab_to_source(_tab), do: nil

  defp normalize_origin(%{"origin" => origin}) when is_binary(origin) and origin != "",
    do: origin

  defp normalize_origin(params) do
    cond do
      params["bank"] not in [nil, "", "all"] ->
        "bank:#{params["bank"]}"

      params["institution_id"] not in [nil, "", "all"] ->
        "institution:#{params["institution_id"]}"

      true ->
        "all"
    end
  end

  defp normalize_kind(%{"kind" => kind}) when is_binary(kind) and kind != "", do: kind

  defp normalize_kind(params) do
    cond do
      params["category_id"] not in [nil, "", "all"] -> "category:#{params["category_id"]}"
      params["statement_type"] not in [nil, "", "all"] -> "statement:#{params["statement_type"]}"
      params["asset_type"] not in [nil, "", "all"] -> "asset:#{params["asset_type"]}"
      true -> "all"
    end
  end

  defp normalize_movement(%{"movement" => movement}) when is_binary(movement) and movement != "",
    do: movement

  defp normalize_movement(params) do
    cond do
      params["type"] == "debit" -> "expense"
      params["type"] == "credit" -> "income"
      params["type"] == "investment" -> "bank_investment"
      params["operation"] == "compra" -> "purchase"
      params["operation"] == "venda" -> "sale"
      params["operation"] in @dividend_ops -> "dividend"
      params["operation"] == "taxa" -> "fee"
      params["operation"] not in [nil, "", "all"] -> "operation:#{params["operation"]}"
      true -> "all"
    end
  end

  defp normalize_sort_by(sort_by) when sort_by in @sort_fields, do: sort_by
  defp normalize_sort_by(_sort_by), do: "date"

  defp normalize_sort_dir(sort_dir) when sort_dir in @sort_dirs, do: sort_dir
  defp normalize_sort_dir(_sort_dir), do: "desc"

  defp transactions_url(filters, page \\ nil) do
    filters =
      if page && page > 1,
        do: Map.put(filters, :page, page),
        else: filters

    qs = build_query_string(filters)

    case qs do
      "" -> ~p"/transactions"
      _ -> "/transactions?#{qs}"
    end
  end

  defp sort_url(filters, field) do
    next_dir =
      if filters.sort_by == field and filters.sort_dir == "asc",
        do: "desc",
        else: "asc"

    filters
    |> Map.put(:sort_by, field)
    |> Map.put(:sort_dir, next_dir)
    |> Map.delete(:page)
    |> transactions_url()
  end

  defp sort_icon("asc"), do: "hero-chevron-up"
  defp sort_icon(_), do: "hero-chevron-down"

  defp build_query_string(filters) do
    filters
    |> Enum.reject(fn {_k, v} -> v in [nil, "", "all"] end)
    |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)
    |> Enum.join("&")
  end

  defp banking_export_query(filters) do
    %{
      search: filters.search,
      bank: origin_bank(filters.origin),
      statement_type: kind_statement_type(filters.kind),
      type: banking_type(filters.movement),
      category_id: kind_category_id(filters.kind),
      date_from: filters.date_from,
      date_to: filters.date_to,
      amount_min: filters.amount_min,
      amount_max: filters.amount_max,
      internal: filters.internal,
      filter: filters.filter,
      statement_id: statement_id(filters, "banking"),
      sort_by: filters.sort_by,
      sort_dir: filters.sort_dir
    }
    |> build_query_string()
  end

  defp investment_export_query(filters) do
    %{
      search: filters.search,
      operation: export_operation(filters.movement),
      asset_type: kind_asset_type(filters.kind),
      institution_id: origin_institution_id(filters.origin),
      date_from: filters.date_from,
      date_to: filters.date_to,
      amount_min: filters.amount_min,
      amount_max: filters.amount_max,
      statement_id: statement_id(filters, "investments")
    }
    |> build_query_string()
  end

  defp export_operation(movement) do
    case investment_operation(movement) do
      ops when is_list(ops) -> Enum.join(ops, ",")
      op -> op
    end
  end

  # ── Row normalization and summaries ──

  defp banking_row(txn) do
    %{
      id: "banking-#{txn.id}",
      raw_id: txn.id,
      raw: txn,
      source: :banking,
      source_label: "Bancário",
      date: txn.date,
      title: txn.description || "",
      origin_sort: bank_sort(txn),
      kind_sort: category_sort(txn),
      amount_sort: txn.amount |> Decimal.abs() |> Decimal.to_float(),
      selectable?: true
    }
  end

  defp investment_row(txn) do
    %{
      id: "investment-#{txn.id}",
      raw_id: txn.id,
      raw: txn,
      source: :investment,
      source_label: "Investimentos",
      date: txn.date,
      title: txn.asset_ticker || txn.asset_name || "",
      origin_sort: if(txn.institution, do: txn.institution.name, else: ""),
      kind_sort: asset_type_label(txn.asset_type),
      amount_sort: txn.total_amount |> Decimal.abs() |> Decimal.to_float(),
      selectable?: false
    }
  end

  defp sort_rows(rows, field, dir) do
    direction = if dir == "asc", do: :asc, else: :desc
    Enum.sort_by(rows, &sort_key(&1, field), direction)
  end

  defp sort_key(row, "date"), do: {Date.to_gregorian_days(row.date), row.id}

  defp sort_key(row, "description"),
    do: {String.downcase(row.title), Date.to_gregorian_days(row.date)}

  defp sort_key(row, "source"), do: {row.source_label, Date.to_gregorian_days(row.date)}
  defp sort_key(row, "kind"), do: {row.kind_sort, Date.to_gregorian_days(row.date)}
  defp sort_key(row, "amount"), do: {row.amount_sort, Date.to_gregorian_days(row.date)}
  defp sort_key(row, _field), do: {Date.to_gregorian_days(row.date), row.id}

  defp unified_summary(rows) do
    zero = Decimal.new(0)

    Enum.reduce(
      rows,
      %{
        bank_expenses: zero,
        bank_income: zero,
        bank_investments: zero,
        inv_purchases: zero,
        inv_sales: zero,
        inv_dividends: zero,
        inv_fees: zero
      },
      fn
        %{source: :banking, raw: txn}, acc ->
          summarize_banking(txn, acc)

        %{source: :investment, raw: txn}, acc ->
          summarize_investment(txn, acc)
      end
    )
  end

  defp summarize_banking(%{is_internal_transfer: true}, acc), do: acc

  defp summarize_banking(%{type: "credit", amount: amount}, acc) do
    %{acc | bank_income: Decimal.add(acc.bank_income, Decimal.abs(amount))}
  end

  defp summarize_banking(%{type: "debit", amount: amount, category: %{kind: "investment"}}, acc) do
    %{acc | bank_investments: Decimal.add(acc.bank_investments, Decimal.abs(amount))}
  end

  defp summarize_banking(%{type: "debit", amount: amount}, acc) do
    %{acc | bank_expenses: Decimal.add(acc.bank_expenses, Decimal.abs(amount))}
  end

  defp summarize_banking(_txn, acc), do: acc

  defp summarize_investment(%{operation: "compra", total_amount: amount}, acc) do
    %{acc | inv_purchases: Decimal.add(acc.inv_purchases, Decimal.abs(amount))}
  end

  defp summarize_investment(%{operation: "venda", total_amount: amount}, acc) do
    %{acc | inv_sales: Decimal.add(acc.inv_sales, Decimal.abs(amount))}
  end

  defp summarize_investment(%{operation: op, total_amount: amount}, acc)
       when op in @dividend_ops do
    %{acc | inv_dividends: Decimal.add(acc.inv_dividends, Decimal.abs(amount))}
  end

  defp summarize_investment(%{operation: "taxa", total_amount: amount}, acc) do
    %{acc | inv_fees: Decimal.add(acc.inv_fees, Decimal.abs(amount))}
  end

  defp summarize_investment(_txn, acc), do: acc

  # ── Filter value helpers ──

  defp origin_bank("bank:" <> bank), do: bank
  defp origin_bank(_origin), do: nil

  defp origin_institution_id("institution:" <> id), do: id
  defp origin_institution_id(_origin), do: nil

  defp origin_banking?("bank:" <> _bank), do: true
  defp origin_banking?(_origin), do: false

  defp origin_investment?("institution:" <> _id), do: true
  defp origin_investment?(_origin), do: false

  defp kind_statement_type("statement:" <> type), do: type
  defp kind_statement_type(_kind), do: nil

  defp kind_category_id("category:" <> id), do: id
  defp kind_category_id(_kind), do: nil

  defp kind_asset_type("asset:" <> type), do: type
  defp kind_asset_type(_kind), do: nil

  defp kind_banking?("statement:" <> _type), do: true
  defp kind_banking?("category:" <> _id), do: true
  defp kind_banking?(_kind), do: false

  defp kind_investment?("asset:" <> _type), do: true
  defp kind_investment?(_kind), do: false

  defp banking_type("expense"), do: "debit"
  defp banking_type("income"), do: "credit"
  defp banking_type("bank_investment"), do: "investment"
  defp banking_type(_movement), do: nil

  defp investment_operation("purchase"), do: "compra"
  defp investment_operation("sale"), do: "venda"
  defp investment_operation("dividend"), do: @dividend_ops
  defp investment_operation("fee"), do: "taxa"
  defp investment_operation("operation:" <> op), do: op
  defp investment_operation(_movement), do: nil

  defp movement_banking_only?(movement), do: movement in ["expense", "income", "bank_investment"]
  defp movement_investment_only?("operation:" <> _op), do: true

  defp movement_investment_only?(movement),
    do: movement in ["purchase", "sale", "dividend", "fee"]

  defp statement_id(%{statement_id: nil}, _source), do: nil
  defp statement_id(%{statement_id: ""}, _source), do: nil
  defp statement_id(%{statement_id: id, statement_source: source}, source), do: parse_int_opt(id)
  defp statement_id(_filters, _source), do: nil

  defp statement_for?(%{statement_id: id, statement_source: source}, source)
       when id not in [nil, ""],
       do: true

  defp statement_for?(_filters, _source), do: false

  # ── Formatting helpers ──

  defp statement_info(%{statement_id: id, statement_source: "banking"}, user_id)
       when id not in [nil, ""] do
    stmt = Banking.get_statement!(parse_int(id, -1), user_id)

    %{
      label: statement_type_label(stmt.statement_type),
      filename: stmt.filename,
      logo: bank_logo(stmt.bank),
      icon: "hero-banknotes"
    }
  end

  defp statement_info(%{statement_id: id, statement_source: "investments"}, user_id)
       when id not in [nil, ""] do
    stmt = Investments.get_statement!(parse_int(id, -1), user_id)

    %{
      label: if(stmt.institution, do: stmt.institution.name, else: "Investimentos"),
      filename: stmt.filename,
      logo: if(stmt.institution, do: Grana.Investments.Institution.logo_url(stmt.institution)),
      icon: "hero-chart-bar"
    }
  end

  defp statement_info(_filters, _user_id), do: nil

  defp bank_logo("nubank"), do: ~p"/images/nubank-logo.png"
  defp bank_logo("bradesco"), do: ~p"/images/bradesco-logo.png"
  defp bank_logo(_), do: ~p"/images/logo-32.png"

  defp bank_sort(%{bank_statement: %{bank: bank}}) when is_binary(bank), do: bank
  defp bank_sort(_txn), do: ""

  defp category_sort(%{category: %{name: name}}) when is_binary(name), do: name
  defp category_sort(_txn), do: "Sem Categoria"

  defp statement_type_label("fatura"), do: "Fatura"
  defp statement_type_label("extrato"), do: "Extrato"
  defp statement_type_label(_type), do: "Bancário"

  defp format_row_amount(%{source: :banking, raw: txn}), do: format_amount(txn)
  defp format_row_amount(%{source: :investment, raw: txn}), do: format_inv_amount(txn)

  defp amount_class(%{source: :banking, raw: %{type: "credit"}}), do: "text-success"
  defp amount_class(%{source: :banking}), do: "text-error"
  defp amount_class(%{source: :investment, raw: txn}), do: inv_amount_color(txn.operation)

  defp format_amount(txn) do
    prefix =
      case txn.type do
        "credit" -> "+ "
        _ -> "- "
      end

    "#{prefix}R$ #{format_br_number(txn.amount)}"
  end

  defp format_inv_amount(txn) do
    prefix = if txn.operation in @income_ops, do: "+ ", else: "- "
    "#{prefix}R$ #{format_br_number(txn.total_amount)}"
  end

  defp inv_amount_color(operation) when operation in @income_ops, do: "text-success"
  defp inv_amount_color(_), do: "text-error"

  defp asset_type_label(type), do: Constants.asset_type_label(type)

  defp transfer_like?(description), do: Grana.Banking.TransferIdentity.transfer?(description)

  defp recurring_status(statuses, id) do
    Map.get(statuses, id, %{status: "none", pattern: "", editable: false})
  end

  defp recurring_flash("fixed"), do: "Despesa marcada como fixa"
  defp recurring_flash("variable"), do: "Despesa marcada como variável"

  defp format_br_number(amount) do
    str = amount |> Decimal.round(2) |> Decimal.abs() |> Decimal.to_string(:normal)
    [int_part, dec_part] = String.split(str, ".")
    dec_part = String.pad_trailing(dec_part, 2, "0")

    int_part
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.chunk_every(3)
    |> Enum.join(".")
    |> String.reverse()
    |> Kernel.<>(",#{dec_part}")
  end

  # ── Generic helpers ──

  defp maybe_bulk_category(msgs, _ids, cat_id, _user_id) when cat_id <= 0, do: msgs

  defp maybe_bulk_category(msgs, ids, cat_id, user_id) do
    {count, _} = Banking.bulk_update_categories(ids, cat_id, user_id)
    ["#{count} com categoria atualizada" | msgs]
  end

  defp maybe_bulk_recurring(msgs, ids, mode, user_id) when mode in ["fixed", "variable"] do
    {:ok, count} = Banking.bulk_set_recurring_mode(user_id, ids, mode)
    ["#{count} com recorrência atualizada" | msgs]
  end

  defp maybe_bulk_recurring(msgs, _ids, _mode, _user_id), do: msgs

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, ""), do: opts
  defp maybe_add_opt(opts, _key, "all"), do: opts
  defp maybe_add_opt(opts, key, val), do: Keyword.put(opts, key, val)

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_decimal(""), do: nil
  defp parse_decimal(nil), do: nil

  defp parse_decimal(str) do
    case Decimal.parse(str) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp parse_int_opt(nil), do: nil

  defp parse_int_opt(str) do
    case Integer.parse(to_string(str)) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp all_selected?([], _selected), do: false

  defp all_selected?(rows, selected) do
    banking_rows = Enum.filter(rows, & &1.selectable?)
    banking_rows != [] and Enum.all?(banking_rows, &MapSet.member?(selected, &1.raw_id))
  end

  defp page_range(_current, total) when total <= 7, do: Enum.to_list(1..total)

  defp page_range(current, total) do
    cond do
      current <= 3 -> Enum.to_list(1..4) ++ [:dots, total]
      current >= total - 2 -> [1, :dots | Enum.to_list((total - 3)..total)]
      true -> [1, :dots, current - 1, current, current + 1, :dots, total]
    end
  end
end
