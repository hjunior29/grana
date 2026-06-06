defmodule GranaWeb.TransactionsLive do
  use GranaWeb, :live_view

  alias Grana.Banking
  alias Grana.Investments
  alias Grana.Investments.Constants

  @per_page 50
  @banking_sort_fields ~w(date description bank category type amount)
  @banking_sort_dirs ~w(asc desc)

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    categories = Banking.ensure_default_categories(user_id)
    banks = Banking.available_banks(user_id)
    inv_institutions = Investments.available_institutions(user_id)
    inv_asset_types = Investments.available_asset_types(user_id)
    inv_operations = Investments.available_operations(user_id)

    socket =
      socket
      |> assign(:page_title, "Transações")
      |> assign(:tab, "banking")
      |> assign(:categories, categories)
      |> assign(:banks, banks)
      |> assign(:expanded_ids, MapSet.new())
      |> assign(:selected_ids, MapSet.new())
      |> assign(:statement_info, nil)
      |> assign(:inv_statement_info, nil)
      # Investment tab data (defaults)
      |> assign(:inv_institutions, inv_institutions)
      |> assign(:inv_asset_types, inv_asset_types)
      |> assign(:inv_operations, inv_operations)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = params["tab"] || "banking"
    user_id = socket.assigns.current_scope.user.id

    socket =
      socket
      |> assign(:tab, tab)
      |> load_tab_data(tab, params, user_id)

    {:noreply, socket}
  end

  # Banking tab data loading
  defp load_tab_data(socket, "banking", params, user_id) do
    filters = %{
      search: params["search"] || "",
      bank: params["bank"] || "all",
      statement_type: params["statement_type"] || "all",
      type: params["type"] || "all",
      category_id: params["category_id"] || "all",
      date_from: params["date_from"] || "",
      date_to: params["date_to"] || "",
      amount_min: params["amount_min"] || "",
      amount_max: params["amount_max"] || "",
      internal: params["internal"] || "all",
      filter: params["filter"] || "all",
      statement_id: params["statement_id"] || nil,
      sort_by: normalize_sort_by(params["sort_by"]),
      sort_dir: normalize_sort_dir(params["sort_dir"])
    }

    page = parse_int(params["page"], 1)

    opts =
      [page: page, per_page: @per_page]
      |> maybe_add_opt(:search, filters.search)
      |> maybe_add_opt(:bank, filters.bank)
      |> maybe_add_opt(:statement_type, filters.statement_type)
      |> maybe_add_opt(:type, filters.type)
      |> maybe_add_opt(:category_id, filters.category_id)
      |> maybe_add_opt(:date_from, parse_date(filters.date_from))
      |> maybe_add_opt(:date_to, parse_date(filters.date_to))
      |> maybe_add_opt(:amount_min, parse_decimal(filters.amount_min))
      |> maybe_add_opt(:amount_max, parse_decimal(filters.amount_max))
      |> maybe_add_opt(:internal, filters.internal)
      |> maybe_add_opt(:bank_statement_id, parse_int_opt(filters.statement_id))
      |> maybe_add_opt(:sort_by, filters.sort_by)
      |> maybe_add_opt(:sort_dir, filters.sort_dir)

    opts =
      case filters.filter do
        "uncategorized" -> Keyword.put(opts, :uncategorized, true)
        _ -> opts
      end

    {transactions, total} = Banking.list_transactions_paginated(user_id, opts)
    total_pages = max(1, ceil(total / @per_page))
    summary = Banking.transactions_summary(user_id, opts)
    internal_count = Enum.count(transactions, & &1.is_internal_transfer)
    recurring_statuses = Banking.recurring_statuses(user_id, transactions)

    statement_info =
      case filters.statement_id do
        nil ->
          nil

        id ->
          stmt = Banking.get_statement!(parse_int(id, -1), user_id)
          %{id: stmt.id, filename: stmt.filename, bank: stmt.bank}
      end

    socket
    |> assign(:filters, filters)
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:total, total)
    |> assign(:transactions, transactions)
    |> assign(:recurring_statuses, recurring_statuses)
    |> assign(:selected_ids, MapSet.new())
    |> assign(:statement_info, statement_info)
    |> assign(:summary, summary)
    |> assign(:internal_count, internal_count)
    # Ensure investment assigns exist for tab badge
    |> maybe_assign_inv_total(user_id)
  end

  # Investments tab data loading
  defp load_tab_data(socket, "investments", params, user_id) do
    inv_filters = %{
      search: params["search"] || "",
      operation: params["operation"] || "all",
      asset_type: params["asset_type"] || "all",
      institution_id: params["institution_id"] || "all",
      date_from: params["date_from"] || "",
      date_to: params["date_to"] || "",
      amount_min: params["amount_min"] || "",
      amount_max: params["amount_max"] || "",
      statement_id: params["statement_id"] || nil
    }

    page = parse_int(params["page"], 1)

    opts =
      [page: page, per_page: @per_page]
      |> maybe_add_opt(:search, inv_filters.search)
      |> maybe_add_opt(:operation, parse_operations(inv_filters.operation))
      |> maybe_add_opt(:asset_type, inv_filters.asset_type)
      |> maybe_add_opt(:institution_id, inv_filters.institution_id)
      |> maybe_add_opt(:date_from, parse_date(inv_filters.date_from))
      |> maybe_add_opt(:date_to, parse_date(inv_filters.date_to))
      |> maybe_add_opt(:amount_min, parse_decimal(inv_filters.amount_min))
      |> maybe_add_opt(:amount_max, parse_decimal(inv_filters.amount_max))
      |> maybe_add_opt(:statement_id, parse_int_opt(inv_filters.statement_id))

    {transactions, total} = Investments.list_transactions_paginated(user_id, opts)
    total_pages = max(1, ceil(total / @per_page))
    summary = Investments.investments_summary(user_id, opts)

    inv_statement_info =
      case inv_filters.statement_id do
        nil ->
          nil

        id ->
          stmt = Investments.get_statement!(parse_int(id, -1), user_id)
          inst_name = if stmt.institution, do: stmt.institution.name, else: "—"

          inst_logo =
            if stmt.institution, do: Grana.Investments.Institution.logo_url(stmt.institution)

          %{id: stmt.id, filename: stmt.filename, institution: inst_name, logo: inst_logo}
      end

    socket
    |> assign(:inv_filters, inv_filters)
    |> assign(:inv_page, page)
    |> assign(:inv_total_pages, total_pages)
    |> assign(:inv_total, total)
    |> assign(:inv_transactions, transactions)
    |> assign(:inv_summary, summary)
    |> assign(:inv_statement_info, inv_statement_info)
    # Ensure banking assigns exist for tab badge
    |> maybe_assign_banking_total(user_id)
  end

  defp load_tab_data(socket, _unknown_tab, params, user_id) do
    load_tab_data(socket, "banking", params, user_id)
  end

  defp maybe_assign_inv_total(socket, user_id) do
    if Map.has_key?(socket.assigns, :inv_total) do
      socket
    else
      {_, total} = Investments.list_transactions_paginated(user_id, page: 1, per_page: 1)
      assign(socket, :inv_total, total)
    end
  end

  defp maybe_assign_banking_total(socket, user_id) do
    if Map.has_key?(socket.assigns, :total) do
      socket
    else
      {_, total} = Banking.list_transactions_paginated(user_id, page: 1, per_page: 1)
      assign(socket, :total, total)
    end
  end

  # ── Events ──

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/transactions?tab=#{tab}")}
  end

  def handle_event("apply_filters", params, socket) do
    case socket.assigns.tab do
      "banking" ->
        query_params =
          %{
            tab: "banking",
            search: params["search"] || "",
            bank: params["bank"] || "all",
            statement_type: params["statement_type"] || "all",
            type: params["type"] || "all",
            category_id: params["category_id"] || "all",
            date_from: params["date_from"] || "",
            date_to: params["date_to"] || "",
            amount_min: params["amount_min"] || "",
            amount_max: params["amount_max"] || "",
            internal: params["internal"] || "all",
            sort_by: socket.assigns.filters.sort_by,
            sort_dir: socket.assigns.filters.sort_dir
          }
          |> maybe_keep_statement(socket.assigns.filters)
          |> build_query_string()

        {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}

      "investments" ->
        query_params =
          %{
            tab: "investments",
            search: params["search"] || "",
            operation: params["operation"] || "all",
            asset_type: params["asset_type"] || "all",
            institution_id: params["institution_id"] || "all",
            date_from: params["date_from"] || "",
            date_to: params["date_to"] || "",
            amount_min: params["amount_min"] || "",
            amount_max: params["amount_max"] || ""
          }
          |> maybe_keep_statement(socket.assigns.inv_filters)
          |> build_query_string()

        {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}
    end
  end

  def handle_event("clear_filters", _params, socket) do
    tab = socket.assigns.tab
    {:noreply, push_patch(socket, to: ~p"/transactions?tab=#{tab}")}
  end

  def handle_event("clear_statement", _params, socket) do
    case socket.assigns.tab do
      "banking" ->
        filters = %{socket.assigns.filters | statement_id: nil}
        query_params = build_query_string(Map.put(filters, :tab, "banking"))
        {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}

      "investments" ->
        inv_filters = %{socket.assigns.inv_filters | statement_id: nil}
        query_params = build_query_string(Map.put(inv_filters, :tab, "investments"))
        {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}
    end
  end

  def handle_event("search", %{"search" => term}, socket) do
    case socket.assigns.tab do
      "banking" ->
        filters = %{socket.assigns.filters | search: term}
        query_params = build_query_string(Map.put(filters, :tab, "banking"))
        {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}

      "investments" ->
        inv_filters = %{socket.assigns.inv_filters | search: term}
        query_params = build_query_string(Map.put(inv_filters, :tab, "investments"))
        {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}
    end
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    filters = %{socket.assigns.filters | filter: filter}
    query_params = build_query_string(Map.put(filters, :tab, "banking"))
    {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}
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

      query_params = build_query_string(Map.put(socket.assigns.filters, :tab, "banking"))

      socket =
        socket
        |> put_flash(:info, "Categoria atualizada e regra salva")
        |> push_patch(to: "/transactions?page=#{socket.assigns.page}&#{query_params}")

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
        query_params = build_query_string(Map.put(socket.assigns.filters, :tab, "banking"))

        socket =
          socket
          |> put_flash(:info, recurring_flash(mode))
          |> push_patch(to: "/transactions?page=#{socket.assigns.page}&#{query_params}")

        {:noreply, socket}

      {:error, :not_recurring_expense} ->
        {:noreply, put_flash(socket, :error, "Só despesas bancárias podem virar fixas.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar a recorrência.")}
    end
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
    %{transactions: transactions, selected_ids: selected} = socket.assigns
    page_ids = MapSet.new(transactions, & &1.id)

    selected =
      if MapSet.subset?(page_ids, selected),
        do: MapSet.difference(selected, page_ids),
        else: MapSet.union(selected, page_ids)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("bulk-categorize", %{"category_id" => category_id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    ids = MapSet.to_list(socket.assigns.selected_ids)
    cat_id = parse_int(category_id, -1)

    if Banking.category_belongs_to_user?(cat_id, user_id) do
      {count, _} = Banking.bulk_update_categories(ids, cat_id, user_id)
      query_params = build_query_string(Map.put(socket.assigns.filters, :tab, "banking"))

      socket =
        socket
        |> assign(:selected_ids, MapSet.new())
        |> put_flash(:info, "#{count} transação(ões) atualizada(s)")
        |> push_patch(to: "/transactions?page=#{socket.assigns.page}&#{query_params}")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Categoria inválida.")}
    end
  end

  def handle_event("clear-selection", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  # ── Helpers ──

  defp maybe_keep_statement(params, %{statement_id: nil}), do: params
  defp maybe_keep_statement(params, %{statement_id: id}), do: Map.put(params, :statement_id, id)

  defp normalize_sort_by(sort_by) when sort_by in @banking_sort_fields, do: sort_by
  defp normalize_sort_by(_sort_by), do: "date"

  defp normalize_sort_dir(sort_dir) when sort_dir in @banking_sort_dirs, do: sort_dir
  defp normalize_sort_dir(_sort_dir), do: "desc"

  defp recurring_flash("fixed"), do: "Despesa marcada como fixa"
  defp recurring_flash("variable"), do: "Despesa marcada como variável"

  defp build_query_string(filters) do
    filters
    |> Enum.reject(fn {_k, v} -> v in [nil, "", "all"] end)
    |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)
    |> Enum.join("&")
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, ""), do: opts
  defp maybe_add_opt(opts, _key, "all"), do: opts
  defp maybe_add_opt(opts, key, val), do: Keyword.put(opts, key, val)

  defp parse_operations(op) when is_binary(op) do
    if String.contains?(op, ","), do: String.split(op, ","), else: op
  end

  defp parse_operations(op), do: op

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
    case Integer.parse(str) do
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

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-4 sm:mb-8 text-center sm:text-left">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Transações</h1>
          <p class="text-xs sm:text-sm opacity-60 mt-1">
            Visualize e gerencie todas as suas transações
          </p>
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

  defp render_banking_tab(assigns) do
    ~H"""
    <div :if={@statement_info} class="mb-4">
      <div class="badge badge-lg gap-2">
        <img src={bank_logo(@statement_info.bank)} alt="" class="w-4 h-4 rounded-full" />
        Extrato: {@statement_info.filename}
        <button phx-click="clear_statement" class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-x-mark" class="size-3" />
        </button>
      </div>
    </div>

    <div class="card bg-base-200 p-4 mb-6">
      <form id="banking-transactions-filters" phx-change="apply_filters" phx-submit="apply_filters">
        <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
          <div class="col-span-2">
            <input
              type="search"
              name="search"
              value={@filters.search}
              placeholder="Buscar transações..."
              class="input input-bordered input-sm w-full"
              phx-debounce="300"
            />
          </div>
          <div>
            <select name="bank" class="select select-bordered select-sm w-full">
              <option value="all" selected={@filters.bank == "all"}>Todos os bancos</option>
              <option :for={b <- @banks} value={b} selected={@filters.bank == b}>
                {String.capitalize(b)}
              </option>
            </select>
          </div>
          <div>
            <select name="statement_type" class="select select-bordered select-sm w-full">
              <option value="all" selected={@filters.statement_type == "all"}>
                Extrato e Fatura
              </option>
              <option value="extrato" selected={@filters.statement_type == "extrato"}>
                Extrato
              </option>
              <option value="fatura" selected={@filters.statement_type == "fatura"}>
                Fatura
              </option>
            </select>
          </div>
          <div>
            <select name="type" class="select select-bordered select-sm w-full">
              <option value="all" selected={@filters.type == "all"}>Todas transações</option>
              <option value="debit" selected={@filters.type == "debit"}>Despesas</option>
              <option value="credit" selected={@filters.type == "credit"}>Receitas</option>
              <option value="investment" selected={@filters.type == "investment"}>
                Investimentos
              </option>
            </select>
          </div>
          <div>
            <select name="category_id" class="select select-bordered select-sm w-full">
              <option value="all" selected={@filters.category_id == "all"}>
                Todas categorias
              </option>
              <option
                :for={cat <- @categories}
                value={cat.id}
                selected={@filters.category_id == to_string(cat.id)}
              >
                {cat.name}
              </option>
            </select>
          </div>
        </div>
        <div class="grid grid-cols-2 md:grid-cols-5 gap-3 mt-3">
          <div>
            <label class="text-xs opacity-50 mb-1 block">Data início</label>
            <input
              type="date"
              name="date_from"
              value={@filters.date_from}
              class="input input-bordered input-sm w-full"
            />
          </div>
          <div>
            <label class="text-xs opacity-50 mb-1 block">Data fim</label>
            <input
              type="date"
              name="date_to"
              value={@filters.date_to}
              class="input input-bordered input-sm w-full"
            />
          </div>
          <div>
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
          <div>
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
          <div>
            <label class="text-xs opacity-50 mb-1 block">Internas</label>
            <select name="internal" class="select select-bordered select-sm w-full">
              <option value="all" selected={@filters.internal == "all"}>Todas</option>
              <option value="hide" selected={@filters.internal == "hide"}>
                Ocultar internas
              </option>
              <option value="only" selected={@filters.internal == "only"}>Apenas internas</option>
            </select>
          </div>
        </div>
      </form>
      <div class="flex justify-end mt-3">
        <button type="button" phx-click="clear_filters" class="btn btn-error btn-xs">
          Limpar filtros
        </button>
      </div>
    </div>

    <div class="flex items-center gap-4 text-sm mb-3 flex-wrap">
      <span :if={@total == 0} class="opacity-60">Nenhuma transação</span>
      <span :if={@total > 1} class="opacity-60">{@total} transações</span>
      <span :if={@total == 1} class="opacity-60">{@total} transação</span>
      <span class="text-error font-medium">
        Despesas: R$ {format_br_number(@summary.total_expenses)}
      </span>
      <span class="text-success font-medium">
        Receitas: R$ {format_br_number(@summary.total_income)}
      </span>
      <span
        :if={Decimal.compare(@summary.total_investments, 0) == :gt}
        class="text-info font-medium"
      >
        Investimentos: R$ {format_br_number(@summary.total_investments)}
      </span>
      <span
        :if={@internal_count > 0}
        class="opacity-50"
        title="Transferências internas excluídas dos totais"
      >
        <.icon name="hero-arrows-right-left" class="size-3 inline" />
        {@internal_count} interna(s) excluída(s)
      </span>
      <a
        :if={@total > 0}
        href={"/transactions/export?#{build_query_string(@filters)}"}
        class="btn btn-sm gap-1 ml-auto"
      >
        <.icon name="hero-arrow-down-tray" class="size-4" /> Exportar CSV
      </a>
    </div>

    <div
      :if={MapSet.size(@selected_ids) > 0}
      class="flex items-center gap-3 flex-wrap bg-primary/10 border border-primary/20 rounded-lg px-4 py-3 mb-4"
    >
      <span class="text-sm font-medium">
        {MapSet.size(@selected_ids)} selecionada(s)
      </span>
      <form phx-submit="bulk-categorize" class="flex items-center gap-2">
        <select name="category_id" class="select select-bordered select-sm">
          <option :for={cat <- @categories} value={cat.id}>{cat.name}</option>
        </select>
        <button type="submit" class="btn btn-primary btn-sm">Aplicar</button>
      </form>
      <button phx-click="clear-selection" class="btn btn-ghost btn-sm">Limpar</button>
    </div>

    <div :if={@transactions == []} class="text-center py-16">
      <.icon name="hero-document-magnifying-glass" class="size-16 mx-auto mb-4 opacity-20" />
      <h2 class="text-xl font-semibold mb-2">Nenhuma transação encontrada</h2>
      <p class="opacity-60 mb-6">Faça upload de um extrato bancário para começar</p>
      <.link navigate={~p"/upload"} class="btn btn-primary">
        <.icon name="hero-cloud-arrow-up" class="size-5" /> Upload
      </.link>
    </div>

    <div :if={@transactions != []} class="overflow-x-auto">
      <table id="banking-transactions-table" class="table">
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
            <.sortable_header filters={@filters} field="description" label="Descrição" />
            <.sortable_header filters={@filters} field="bank" label="Banco" />
            <.sortable_header filters={@filters} field="category" label="Categoria" />
            <th>Recorrência</th>
            <.sortable_header filters={@filters} field="amount" label="Valor" class="text-right" />
          </tr>
        </thead>
        <tbody>
          <tr
            :for={txn <- @transactions}
            id={"banking-transaction-#{txn.id}"}
            class={["hover", txn.is_internal_transfer && "opacity-50"]}
          >
            <td>
              <input
                type="checkbox"
                class="checkbox checkbox-xs"
                checked={MapSet.member?(@selected_ids, txn.id)}
                phx-click="toggle-select"
                phx-value-id={txn.id}
              />
            </td>
            <td class="text-sm whitespace-nowrap">{Calendar.strftime(txn.date, "%d/%m/%Y")}</td>
            <td class="text-sm max-w-xs">
              <div class="flex items-center gap-2">
                <span
                  class={[
                    "cursor-pointer hover:opacity-70",
                    !MapSet.member?(@expanded_ids, txn.id) && "truncate"
                  ]}
                  phx-click="toggle-description"
                  phx-value-id={txn.id}
                  title={
                    if !MapSet.member?(@expanded_ids, txn.id),
                      do: txn.original_description || txn.description
                  }
                >
                  {txn.description}
                </span>
                <span
                  :if={txn.is_internal_transfer}
                  class="badge badge-xs badge-ghost shrink-0 opacity-60"
                  title="Transferência interna — excluída dos totais"
                >
                  interna
                </span>
              </div>
            </td>
            <td>
              <span :if={txn.bank_statement} class="badge badge-sm badge-ghost gap-1">
                <div class="w-4 h-4 rounded-full overflow-hidden bg-base-300 shrink-0">
                  <img src={bank_logo(txn.bank_statement.bank)} alt="" />
                </div>
                {String.capitalize(txn.bank_statement.bank)}
              </span>
            </td>
            <td>
              <%!-- Select sempre visível, estilizado como o badge: 1 clique abre o menu
                    nativo (sem a troca badge→select que pedia 2 cliques) e o popup nativo
                    não é cortado pelo overflow-x da tabela. --%>
              <form id={"transaction-category-form-#{txn.id}"} phx-change="save-category">
                <input type="hidden" name="txn_id" value={txn.id} />
                <select
                  name="category_id"
                  aria-label="Categoria"
                  title="Alterar categoria"
                  class={
                    [
                      # Mesmo visual do badge antigo (pílula colorida, sem setinha nem
                      # caixa de select): appearance-none remove a seta nativa.
                      "badge badge-sm font-medium appearance-none cursor-pointer max-w-40",
                      !txn.category && "badge-warning"
                    ]
                  }
                  style={
                    txn.category &&
                      "background-color: #{txn.category.color}20; color: #{txn.category.color}; border-color: #{txn.category.color}40"
                  }
                >
                  <option
                    :for={cat <- @categories}
                    value={cat.id}
                    selected={txn.category_id == cat.id}
                  >
                    {cat.name}
                  </option>
                </select>
              </form>
            </td>
            <td>{render_recurring_cell(assigns, txn)}</td>
            <td class={[
              "text-right text-sm font-medium whitespace-nowrap",
              (txn.type == "credit" && "text-success") || "text-error"
            ]}>
              {format_amount(txn)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div :if={@total_pages > 1} class="flex justify-center gap-2 mt-6">
      <.link
        :if={@page > 1}
        patch={page_url(%{tab: "banking"}, @filters, @page - 1)}
        class="btn btn-sm btn-ghost"
      >
        <.icon name="hero-chevron-left" class="size-4" />
      </.link>
      <span :for={p <- page_range(@page, @total_pages)}>
        <.link
          :if={is_integer(p)}
          patch={page_url(%{tab: "banking"}, @filters, p)}
          class={["btn btn-sm", (p == @page && "btn-primary") || "btn-ghost"]}
        >
          {p}
        </.link>
        <span :if={p == :dots} class="px-2 opacity-40">...</span>
      </span>
      <.link
        :if={@page < @total_pages}
        patch={page_url(%{tab: "banking"}, @filters, @page + 1)}
        class="btn btn-sm btn-ghost"
      >
        <.icon name="hero-chevron-right" class="size-4" />
      </.link>
    </div>
    """
  end

  defp render_investments_tab(assigns) do
    ~H"""
    <div :if={@inv_statement_info} class="mb-4">
      <div class="badge badge-lg gap-2">
        <div
          :if={@inv_statement_info.logo}
          class="w-4 h-4 rounded-full overflow-hidden bg-base-300 shrink-0"
        >
          <img src={@inv_statement_info.logo} alt="" />
        </div>
        <.icon :if={!@inv_statement_info.logo} name="hero-chart-bar" class="size-4" />
        {@inv_statement_info.institution}: {@inv_statement_info.filename}
        <button phx-click="clear_statement" class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-x-mark" class="size-3" />
        </button>
      </div>
    </div>

    <div class="card bg-base-200 p-4 mb-6">
      <form phx-change="apply_filters" phx-submit="apply_filters">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div class="col-span-2">
            <input
              type="search"
              name="search"
              value={@inv_filters.search}
              placeholder="Buscar por ativo..."
              class="input input-bordered input-sm w-full"
              phx-debounce="300"
            />
          </div>
          <div>
            <select name="operation" class="select select-bordered select-sm w-full">
              <option value="all" selected={@inv_filters.operation == "all"}>
                Todas operações
              </option>
              <option :for={op <- @inv_operations} value={op} selected={@inv_filters.operation == op}>
                {operation_label(op)}
              </option>
            </select>
          </div>
          <div>
            <select name="asset_type" class="select select-bordered select-sm w-full">
              <option value="all" selected={@inv_filters.asset_type == "all"}>
                Todos os tipos
              </option>
              <option
                :for={at <- @inv_asset_types}
                value={at}
                selected={@inv_filters.asset_type == at}
              >
                {asset_type_label(at)}
              </option>
            </select>
          </div>
        </div>
        <div class="grid grid-cols-2 md:grid-cols-5 gap-3 mt-3">
          <div>
            <label class="text-xs opacity-50 mb-1 block">Instituição</label>
            <select name="institution_id" class="select select-bordered select-sm w-full">
              <option value="all" selected={@inv_filters.institution_id == "all"}>
                Todas instituições
              </option>
              <option
                :for={inst <- @inv_institutions}
                value={inst.id}
                selected={@inv_filters.institution_id == to_string(inst.id)}
              >
                {inst.name}
              </option>
            </select>
          </div>
          <div>
            <label class="text-xs opacity-50 mb-1 block">Data início</label>
            <input
              type="date"
              name="date_from"
              value={@inv_filters.date_from}
              class="input input-bordered input-sm w-full"
            />
          </div>
          <div>
            <label class="text-xs opacity-50 mb-1 block">Data fim</label>
            <input
              type="date"
              name="date_to"
              value={@inv_filters.date_to}
              class="input input-bordered input-sm w-full"
            />
          </div>
          <div>
            <label class="text-xs opacity-50 mb-1 block">Valor mínimo</label>
            <input
              type="number"
              name="amount_min"
              value={@inv_filters.amount_min}
              step="0.01"
              placeholder="0,00"
              class="input input-bordered input-sm w-full"
            />
          </div>
          <div>
            <label class="text-xs opacity-50 mb-1 block">Valor máximo</label>
            <input
              type="number"
              name="amount_max"
              value={@inv_filters.amount_max}
              step="0.01"
              placeholder="0,00"
              class="input input-bordered input-sm w-full"
            />
          </div>
        </div>
      </form>
      <div class="flex justify-end mt-3">
        <button type="button" phx-click="clear_filters" class="btn btn-error btn-xs">
          Limpar filtros
        </button>
      </div>
    </div>

    <div class="flex items-center gap-4 text-sm mb-3 flex-wrap">
      <span :if={@inv_total == 0} class="opacity-60">Nenhuma transação</span>
      <span :if={@inv_total > 1} class="opacity-60">{@inv_total} transações</span>
      <span :if={@inv_total == 1} class="opacity-60">{@inv_total} transação</span>
      <span :if={Decimal.compare(@inv_summary.total_compras, 0) == :gt} class="text-info font-medium">
        Compras: R$ {format_br_number(@inv_summary.total_compras)}
      </span>
      <span
        :if={Decimal.compare(@inv_summary.total_vendas, 0) == :gt}
        class="text-warning font-medium"
      >
        Vendas: R$ {format_br_number(@inv_summary.total_vendas)}
      </span>
      <span
        :if={Decimal.compare(@inv_summary.total_proventos, 0) == :gt}
        class="text-success font-medium"
      >
        Proventos: R$ {format_br_number(@inv_summary.total_proventos)}
      </span>
      <span :if={Decimal.compare(@inv_summary.total_taxas, 0) == :gt} class="text-error font-medium">
        Taxas: R$ {format_br_number(@inv_summary.total_taxas)}
      </span>
      <a
        :if={@inv_total > 0}
        href={"/transactions/export/investments?#{build_query_string(@inv_filters)}"}
        class="btn btn-sm gap-1 ml-auto"
      >
        <.icon name="hero-arrow-down-tray" class="size-4" /> Exportar CSV
      </a>
    </div>

    <div :if={@inv_transactions == []} class="text-center py-16">
      <.icon name="hero-document-magnifying-glass" class="size-16 mx-auto mb-4 opacity-20" />
      <h2 class="text-xl font-semibold mb-2">Nenhuma transação de investimento</h2>
      <p class="opacity-60 mb-6">Importe seus extratos de investimento para começar</p>
      <.link navigate={~p"/upload"} class="btn btn-primary">
        <.icon name="hero-cloud-arrow-up" class="size-5" /> Upload
      </.link>
    </div>

    <div :if={@inv_transactions != []} class="overflow-x-auto">
      <table class="table">
        <thead>
          <tr>
            <th>Data</th>
            <th>Ativo</th>
            <th>Operação</th>
            <th>Instituição</th>
            <th>Tipo</th>
            <th class="text-right">Valor</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={txn <- @inv_transactions} class="hover">
            <td class="text-sm whitespace-nowrap">{Calendar.strftime(txn.date, "%d/%m/%Y")}</td>
            <td class="text-sm">
              <div>
                <span class="font-medium">{txn.asset_ticker || txn.asset_name}</span>
                <span
                  :if={txn.asset_ticker && txn.asset_name != txn.asset_ticker}
                  class="text-xs opacity-50 block truncate max-w-48"
                  title={txn.asset_name}
                >
                  {txn.asset_name}
                </span>
              </div>
            </td>
            <td>
              <span class={[
                "badge badge-sm",
                operation_badge_class(txn.operation)
              ]}>
                {operation_label(txn.operation)}
              </span>
            </td>
            <td>
              <span :if={txn.institution} class="badge badge-sm badge-ghost gap-1">
                <div class="w-4 h-4 rounded-full overflow-hidden bg-base-300 shrink-0">
                  <img src={Grana.Investments.Institution.logo_url(txn.institution)} alt="" />
                </div>
                {txn.institution.name}
              </span>
            </td>
            <td>
              <span class="badge badge-sm badge-outline whitespace-nowrap">
                {asset_type_label(txn.asset_type)}
              </span>
            </td>
            <td class={[
              "text-right text-sm font-medium whitespace-nowrap",
              inv_amount_color(txn.operation)
            ]}>
              {format_inv_amount(txn)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div :if={@inv_total_pages > 1} class="flex justify-center gap-2 mt-6">
      <.link
        :if={@inv_page > 1}
        patch={page_url(%{tab: "investments"}, @inv_filters, @inv_page - 1)}
        class="btn btn-sm btn-ghost"
      >
        <.icon name="hero-chevron-left" class="size-4" />
      </.link>
      <span :for={p <- page_range(@inv_page, @inv_total_pages)}>
        <.link
          :if={is_integer(p)}
          patch={page_url(%{tab: "investments"}, @inv_filters, p)}
          class={["btn btn-sm", (p == @inv_page && "btn-primary") || "btn-ghost"]}
        >
          {p}
        </.link>
        <span :if={p == :dots} class="px-2 opacity-40">...</span>
      </span>
      <.link
        :if={@inv_page < @inv_total_pages}
        patch={page_url(%{tab: "investments"}, @inv_filters, @inv_page + 1)}
        class="btn btn-sm btn-ghost"
      >
        <.icon name="hero-chevron-right" class="size-4" />
      </.link>
    </div>
    """
  end

  # ── Formatting helpers ──

  defp sortable_header(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <th class={@class}>
      <.link
        patch={sort_url(@filters, @field)}
        class={[
          "inline-flex items-center gap-1 rounded-md transition hover:text-primary",
          @class == "text-right" && "justify-end w-full"
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

  defp render_recurring_cell(assigns, txn) do
    assigns =
      assigns
      |> assign(:txn, txn)
      |> assign(:recurring, recurring_status(assigns.recurring_statuses, txn.id))

    ~H"""
    <div class="min-w-24">
      <form
        :if={@recurring.editable}
        id={"transaction-recurring-form-#{@txn.id}"}
        phx-change="save-recurring"
      >
        <input type="hidden" name="txn_id" value={@txn.id} />
        <select
          name="mode"
          aria-label="Recorrência da despesa"
          title="Alterar recorrência"
          class={
            [
              # Mesmo visual do chip antigo (badge), sem setinha nem caixa de select.
              "badge badge-sm font-medium appearance-none cursor-pointer",
              recurring_select_class(@recurring.status)
            ]
          }
        >
          <option value="fixed" selected={@recurring.status == "fixed"}>Fixa</option>
          <option value="variable" selected={@recurring.status == "variable"}>Variável</option>
        </select>
      </form>

      <span :if={!@recurring.editable} class="text-xs opacity-30">—</span>
    </div>
    """
  end

  # Cores do select de recorrência: roxo para fixa, cinza para variável (mesmo
  # esquema do antigo chip).
  defp recurring_select_class("fixed"), do: "border-primary/40 bg-primary/10 text-primary"

  defp recurring_select_class(_),
    do: "border-base-content/20 bg-base-content/5 text-base-content/60"

  defp sort_url(filters, field) do
    next_dir =
      if filters.sort_by == field and filters.sort_dir == "asc",
        do: "desc",
        else: "asc"

    qs =
      filters
      |> Map.put(:tab, "banking")
      |> Map.put(:sort_by, field)
      |> Map.put(:sort_dir, next_dir)
      |> build_query_string()

    "/transactions?#{qs}"
  end

  defp sort_icon("asc"), do: "hero-chevron-up"
  defp sort_icon(_), do: "hero-chevron-down"

  defp recurring_status(statuses, id) do
    Map.get(statuses, id, %{status: "none", pattern: "", editable: false})
  end

  defp page_url(base, filters, page) do
    qs = build_query_string(Map.merge(filters, Map.put(base, :page, page)))
    "/transactions?#{qs}"
  end

  defp bank_logo("nubank"), do: ~p"/images/nubank-logo.png"
  defp bank_logo("bradesco"), do: ~p"/images/bradesco-logo.png"
  defp bank_logo(_), do: ~p"/images/logo-32.png"

  defp format_amount(txn) do
    prefix =
      case txn.type do
        "credit" -> "+ "
        _ -> "- "
      end

    "#{prefix}R$ #{format_br_number(txn.amount)}"
  end

  @income_ops ~w(venda) ++ Constants.dividend_ops()

  defp format_inv_amount(txn) do
    prefix = if txn.operation in @income_ops, do: "+ ", else: "- "
    "#{prefix}R$ #{format_br_number(txn.total_amount)}"
  end

  defp inv_amount_color(operation) when operation in @income_ops, do: "text-success"
  defp inv_amount_color(_), do: "text-error"

  defp operation_label(op), do: Constants.operation_label(op)

  defp operation_badge_class(op) when op in unquote(Constants.dividend_ops()),
    do: "badge-success"

  defp operation_badge_class("compra"), do: "badge-info"
  defp operation_badge_class("venda"), do: "badge-warning"
  defp operation_badge_class("taxa"), do: "badge-error"
  defp operation_badge_class(_), do: "badge-ghost"

  defp asset_type_label(type), do: Constants.asset_type_label(type)

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

  defp all_selected?([], _selected), do: false

  defp all_selected?(transactions, selected) do
    Enum.all?(transactions, &MapSet.member?(selected, &1.id))
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
