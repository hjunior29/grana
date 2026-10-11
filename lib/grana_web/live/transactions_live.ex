defmodule GranaWeb.TransactionsLive do
  use GranaWeb, :live_view

  alias Grana.Banking
  alias Grana.OpenFinance

  @per_page 50
  @sort_fields ~w(date description source kind amount)
  @sort_dirs ~w(asc desc)

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    socket =
      socket
      |> assign(:page_title, "Transações")
      |> assign(:categories, Banking.ensure_default_categories(user_id))
      |> assign(:banks, Banking.available_banks(user_id))
      |> assign(:expanded_ids, MapSet.new())
      |> assign(:selected_ids, MapSet.new())

    # Meses sem upload vêm do Open Finance; relê se a última leitura passou de 1h.
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Grana.PubSub, OpenFinance.topic(user_id))
      OpenFinance.refresh_if_stale(socket.assigns.current_scope)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:open_finance_synced, _connection_id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    {:noreply,
     socket
     |> assign(:banks, Banking.available_banks(user_id))
     |> load_transactions(user_id)}
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

    banking_transactions = Banking.list_transactions(user_id, banking_opts(filters))

    all_rows =
      banking_transactions
      |> Enum.map(&banking_row/1)
      |> sort_rows(filters.sort_by, filters.sort_dir)

    total = length(all_rows)
    total_pages = max(1, ceil(total / @per_page))
    page = min(page, total_pages)
    page_rows = Enum.slice(all_rows, (page - 1) * @per_page, @per_page)
    visible_banking = Enum.map(page_rows, & &1.raw)

    socket
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:total, total)
    |> assign(:banking_total, total)
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

  defp maybe_uncategorized(opts, %{filter: "uncategorized"}),
    do: Keyword.put(opts, :uncategorized, true)

  defp maybe_uncategorized(opts, _filters), do: opts

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <.page_header
          title="Transações"
          subtitle="Visualize e gerencie todas as suas transações em uma lista única"
        />

        <div :if={@statement_info} class="mb-4">
          <.tag kind="neutro" class="gap-2 py-1">
            <img
              :if={@statement_info.logo}
              src={@statement_info.logo}
              alt=""
              class="w-4 h-4 rounded-full"
            />
            <.icon :if={!@statement_info.logo} name={@statement_info.icon} class="size-4" />
            {@statement_info.label}: {@statement_info.filename}
            <button
              type="button"
              phx-click="clear_statement"
              class="ui-chip -mr-1 h-5 px-1"
              aria-label="Remover filtro de extrato"
            >
              <.icon name="hero-x-mark" class="size-3" />
            </button>
          </.tag>
        </div>

        <div class="mb-3 sm:hidden">
          <.button
            id="transactions-filters-toggle"
            type="button"
            variant="secondary"
            size="sm"
            icon="hero-funnel"
            phx-click={JS.toggle_class("hidden", to: "#transactions-filters-card")}
          >
            Filtros
          </.button>
        </div>

        <div
          id="transactions-filters-card"
          class={["card bg-base-200 p-4 mb-6", !filtered?(@filters) && "hidden sm:block"]}
        >
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
                <.input
                  type="search"
                  name="search"
                  label="Buscar"
                  size="sm"
                  value={@filters.search}
                  placeholder="Transação ou categoria"
                  phx-debounce="300"
                />
              </div>

              <div class="transactions-filter-movement">
                <.input
                  type="select"
                  name="movement"
                  label="Movimento"
                  size="sm"
                  value={@filters.movement}
                  options={[
                    {"Todos movimentos", "all"},
                    {"Despesas", "expense"},
                    {"Receitas", "income"},
                    {"Investimentos", "bank_investment"}
                  ]}
                />
              </div>

              <div class="transactions-filter-origin">
                <.input
                  type="select"
                  name="origin"
                  label="Origem"
                  size="sm"
                  value={@filters.origin}
                  options={[
                    {"Todas origens", "all"}
                    | for(b <- @banks, do: {String.capitalize(b), "bank:#{b}"})
                  ]}
                />
              </div>

              <div class="transactions-filter-kind">
                <.input
                  type="select"
                  name="kind"
                  label="Tipo ou categoria"
                  size="sm"
                  value={@filters.kind}
                  options={
                    [
                      {"Todos os tipos", "all"},
                      {"Extrato", "statement:extrato"},
                      {"Fatura", "statement:fatura"}
                    ] ++ for(cat <- @categories, do: {cat.name, "category:#{cat.id}"})
                  }
                />
              </div>

              <div class="transactions-filter-date-from">
                <.input
                  type="date"
                  name="date_from"
                  label="Data início"
                  size="sm"
                  value={@filters.date_from}
                />
              </div>

              <div class="transactions-filter-date-to">
                <.input
                  type="date"
                  name="date_to"
                  label="Data fim"
                  size="sm"
                  value={@filters.date_to}
                />
              </div>

              <div class="transactions-filter-min">
                <.input
                  type="number"
                  name="amount_min"
                  label="Valor mínimo"
                  size="sm"
                  value={@filters.amount_min}
                  step="0.01"
                  placeholder="0,00"
                />
              </div>

              <div class="transactions-filter-max">
                <.input
                  type="number"
                  name="amount_max"
                  label="Valor máximo"
                  size="sm"
                  value={@filters.amount_max}
                  step="0.01"
                  placeholder="0,00"
                />
              </div>

              <div class="transactions-filter-internal">
                <.input
                  type="select"
                  name="internal"
                  label="Transferências internas"
                  size="sm"
                  value={@filters.internal}
                  options={[
                    {"Todas", "all"},
                    {"Ocultar internas", "hide"},
                    {"Apenas internas", "only"}
                  ]}
                />
              </div>

              <div class="transactions-filter-clear flex items-end justify-end">
                <.button
                  id="clear-filters"
                  type="button"
                  variant="ghost"
                  size="sm"
                  class="mb-2"
                  phx-click="clear_filters"
                >
                  Limpar filtros
                </.button>
              </div>
            </div>
          </form>
        </div>

        <div class="ui-body mb-3 flex flex-wrap items-center gap-x-4 gap-y-2">
          <span :if={@total == 0} class="ui-text-secondary">Nenhuma transação</span>
          <span :if={@total > 1} class="ui-text-secondary">{@total} transações</span>
          <span :if={@total == 1} class="ui-text-secondary">{@total} transação</span>
          <span :if={Decimal.compare(@summary.bank_expenses, 0) == :gt} class="font-medium">
            Despesas <.money value={@summary.bank_expenses} tone={:despesa} />
          </span>
          <span :if={Decimal.compare(@summary.bank_income, 0) == :gt} class="font-medium">
            Receitas <.money value={@summary.bank_income} tone={:receita} />
          </span>
          <span :if={Decimal.compare(@summary.bank_investments, 0) == :gt} class="font-medium">
            Investimentos <.money value={@summary.bank_investments} tone={:investimento} />
          </span>

          <div :if={@total > 0} class="ml-auto flex gap-2">
            <.button
              id="export-csv"
              href={"/transactions/export?#{banking_export_query(@filters)}"}
              variant="secondary"
              size="sm"
              icon="hero-arrow-down-tray"
            >
              Exportar CSV
            </.button>
          </div>
        </div>

        <div
          :if={MapSet.size(@selected_ids) > 0}
          id="bulk-bar"
          class="ui-rounded-box mb-4 flex flex-wrap items-end gap-x-4 gap-y-2 border border-primary/20 bg-primary/10 px-4 py-3"
        >
          <span class="ui-body mb-2 whitespace-nowrap font-medium">
            {MapSet.size(@selected_ids)} {if MapSet.size(@selected_ids) == 1,
              do: "selecionada",
              else: "selecionadas"}
          </span>
          <form phx-submit="bulk-apply" class="flex flex-wrap items-end gap-x-3 gap-y-2">
            <.input
              type="select"
              name="category_id"
              label="Categoria"
              size="sm"
              value={nil}
              prompt="Manter"
              options={for cat <- @categories, do: {cat.name, cat.id}}
            />
            <.input
              type="select"
              name="mode"
              label="Recorrência"
              size="sm"
              value={nil}
              prompt="Manter"
              options={[{"Fixa", "fixed"}, {"Variável", "variable"}]}
            />
            <div class="mb-2">
              <.button variant="primary" size="sm" loading="Aplicando…">Aplicar</.button>
            </div>
          </form>
          <div class="mb-2 ml-auto">
            <.button type="button" variant="ghost" size="sm" phx-click="clear-selection">
              Limpar seleção
            </.button>
          </div>
        </div>

        <.empty_state
          :if={@transactions == [] && filtered?(@filters)}
          id="transactions-empty"
          icon="hero-document-magnifying-glass"
          title="Nada com esses filtros"
          text="Tente outros termos ou limpe os filtros."
        >
          <:action>
            <.button type="button" variant="secondary" size="sm" phx-click="clear_filters">
              Limpar filtros
            </.button>
          </:action>
        </.empty_state>

        <.empty_state
          :if={@transactions == [] && !filtered?(@filters)}
          id="transactions-empty"
          icon="hero-document-magnifying-glass"
          title="Nenhuma transação ainda"
          text="Importe dados bancários ou de investimento para começar."
        >
          <:action>
            <.button navigate={~p"/upload"} variant="primary" icon="hero-cloud-arrow-up">
              Importar extratos
            </.button>
          </:action>
        </.empty_state>

        <div :if={@transactions != []} class="mb-3 flex flex-wrap items-center gap-1 sm:hidden">
          <span class="ui-caption mr-1">Ordenar</span>
          <.link
            :for={
              {field, label} <- [{"date", "Data"}, {"description", "Transação"}, {"amount", "Valor"}]
            }
            patch={sort_url(@filters, field)}
            class={["ui-chip", @filters.sort_by == field && "ui-chip-active"]}
          >
            {label}
            <.icon
              :if={@filters.sort_by == field}
              name={sort_icon(@filters.sort_dir)}
              class="size-3"
            />
          </.link>
        </div>

        <div
          :if={@transactions != []}
          class="transactions-table-shell card bg-base-200 overflow-x-auto"
        >
          <table id="transactions-table" class="table">
            <thead class="hidden sm:table-header-group">
              <tr>
                <th class="w-8">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs"
                    aria-label="Selecionar todas"
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
                  row.source == :banking && row.raw.is_internal_transfer && "ui-text-tertiary"
                ]}
              >
                <td class="ui-txn-select">
                  <input
                    :if={row.selectable?}
                    type="checkbox"
                    class="checkbox checkbox-xs"
                    aria-label="Selecionar transação"
                    checked={MapSet.member?(@selected_ids, row.raw_id)}
                    phx-click="toggle-select"
                    phx-value-id={row.raw_id}
                  />
                  <span :if={row.selectable?} class="ui-caption sm:hidden">
                    Selecionar para ação em lote
                  </span>
                  <span :if={!row.selectable?} class="ui-text-tertiary hidden sm:inline">—</span>
                </td>
                <td
                  class="ui-txn-date ui-body whitespace-nowrap"
                  phx-click={toggle_row(row)}
                >
                  <span class="sm:hidden">{Calendar.strftime(row.date, "%d/%m")}</span>
                  <span class="hidden sm:inline">{Calendar.strftime(row.date, "%d/%m/%Y")}</span>
                </td>
                <td class="ui-txn-title ui-body max-w-xs">{render_title_cell(assigns, row)}</td>
                <td class="ui-txn-detail">
                  <span class="ui-caption sm:hidden">Origem</span>
                  {render_origin_cell(row)}
                  <button
                    :if={
                      row.source == :banking and not row.raw.is_internal_transfer and
                        transfer_like?(row.raw.description)
                    }
                    type="button"
                    phx-click="toggle-internal"
                    phx-value-id={row.raw_id}
                    phx-value-internal="true"
                    class="ui-tag ui-tag-neutro mt-2 cursor-pointer sm:hidden"
                  >
                    Marcar como interna
                  </button>
                </td>
                <td class="ui-txn-detail text-center">
                  <span class="ui-caption sm:hidden">Classificação</span>
                  {render_kind_cell(assigns, row)}
                </td>
                <td class="ui-txn-detail text-center">
                  <span class="ui-caption sm:hidden">Recorrência</span>
                  {render_recurring_column(assigns, row)}
                </td>
                <td class="ui-txn-amount text-right" phx-click={toggle_row(row)}>
                  <.money
                    value={signed_amount(row)}
                    tone={:auto}
                    sign
                    class="ui-body font-medium"
                  />
                  <.icon
                    name="hero-chevron-down"
                    class="ui-txn-chevron ui-text-tertiary ml-1 size-3 sm:hidden"
                  />
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
            <span :if={p == :dots} class="ui-text-tertiary px-2">…</span>
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

  defp render_title_cell(assigns, row) do
    assigns = assign(assigns, :row, row)

    ~H"""
    <div class="flex items-center gap-2">
      <span
        class={[
          "cursor-pointer hover:text-primary",
          !MapSet.member?(@expanded_ids, @row.raw_id) && "truncate"
        ]}
        phx-click={
          JS.push("toggle-description", value: %{id: to_string(@row.raw_id)})
          |> JS.toggle_class("ui-row-open", to: "#transaction-#{@row.id}")
        }
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
        class="ui-tag ui-tag-neutro shrink-0 cursor-pointer"
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
        class="ui-tag ui-tag-neutro ui-text-tertiary hidden shrink-0 cursor-pointer sm:inline-flex"
        title="Marcar como transferência interna (entre suas contas)"
      >
        marcar interna
      </button>
    </div>
    """
  end

  defp render_origin_cell(%{raw: txn}) do
    assigns = %{txn: txn}

    ~H"""
    <.source_chip
      :if={@txn.bank_statement}
      bank={@txn.bank_statement.bank}
      type={@txn.bank_statement.statement_type}
      open_finance={@txn.bank_statement.source == "open_finance"}
    />
    """
  end

  defp render_kind_cell(assigns, row) do
    assigns = assign(assigns, :row, row)

    ~H"""
    <form
      id={"transaction-category-form-#{@row.raw_id}"}
      phx-change="save-category"
      class="flex items-center justify-center gap-2"
    >
      <input type="hidden" name="txn_id" value={@row.raw_id} />
      <.category_icon category={@row.raw.category} />
      <select
        name="category_id"
        aria-label="Categoria"
        title="Alterar categoria"
        class={[
          "select select-sm w-full max-w-44",
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

  defp render_recurring_column(assigns, row) do
    render_recurring_cell(assigns, row.raw)
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
          class="select select-sm w-full"
        >
          <option value="fixed" selected={@recurring.status == "fixed"}>Fixa</option>
          <option value="variable" selected={@recurring.status == "variable"}>Variável</option>
        </select>
      </form>

      <span :if={!@recurring.editable} class="ui-text-tertiary inline-flex w-full justify-center">
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
          "inline-flex items-center gap-1 transition hover:text-primary",
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

  defp filtered?(filters) do
    filters
    |> Map.drop([:sort_by, :sort_dir])
    |> Map.values()
    |> Enum.any?(&(&1 not in [nil, "", "all"]))
  end

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

  defp normalize_source(source) when source in ["all", "banking"], do: source
  defp normalize_source(_source), do: "all"

  defp normalize_statement_source(_source), do: "banking"

  defp tab_to_source(_tab), do: nil

  defp normalize_origin(%{"origin" => origin}) when is_binary(origin) and origin != "",
    do: origin

  defp normalize_origin(params) do
    if params["bank"] not in [nil, "", "all"],
      do: "bank:#{params["bank"]}",
      else: "all"
  end

  defp normalize_kind(%{"kind" => kind}) when is_binary(kind) and kind != "", do: kind

  defp normalize_kind(params) do
    cond do
      params["category_id"] not in [nil, "", "all"] -> "category:#{params["category_id"]}"
      params["statement_type"] not in [nil, "", "all"] -> "statement:#{params["statement_type"]}"
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
        bank_investments: zero
      },
      fn %{source: :banking, raw: txn}, acc ->
        summarize_banking(txn, acc)
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

  # ── Filter value helpers ──

  defp origin_bank("bank:" <> bank), do: bank
  defp origin_bank(_origin), do: nil

  defp kind_statement_type("statement:" <> type), do: type
  defp kind_statement_type(_kind), do: nil

  defp kind_category_id("category:" <> id), do: id
  defp kind_category_id(_kind), do: nil

  defp banking_type("expense"), do: "debit"
  defp banking_type("income"), do: "credit"
  defp banking_type("bank_investment"), do: "investment"
  defp banking_type(_movement), do: nil

  defp statement_id(%{statement_id: nil}, _source), do: nil
  defp statement_id(%{statement_id: ""}, _source), do: nil
  defp statement_id(%{statement_id: id, statement_source: source}, source), do: parse_int_opt(id)
  defp statement_id(_filters, _source), do: nil

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

  defp signed_amount(%{raw: %{type: "credit", amount: amount}}), do: Decimal.abs(amount)
  defp signed_amount(%{raw: %{amount: amount}}), do: amount |> Decimal.abs() |> Decimal.negate()

  defp toggle_row(row), do: JS.toggle_class("ui-row-open", to: "#transaction-#{row.id}")

  defp transfer_like?(description), do: Grana.Banking.TransferIdentity.transfer?(description)

  defp recurring_status(statuses, id) do
    Map.get(statuses, id, %{status: "none", pattern: "", editable: false})
  end

  defp recurring_flash("fixed"), do: "Despesa marcada como fixa"
  defp recurring_flash("variable"), do: "Despesa marcada como variável"

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
