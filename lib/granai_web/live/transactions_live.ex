defmodule GranaiWeb.TransactionsLive do
  use GranaiWeb, :live_view

  alias Grana.Banking

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    categories = Banking.ensure_default_categories(user_id)
    banks = Banking.available_banks(user_id)

    socket =
      socket
      |> assign(:page_title, "Transações")
      |> assign(:categories, categories)
      |> assign(:banks, banks)
      |> assign(:editing_id, nil)
      |> assign(:expanded_ids, MapSet.new())
      |> assign(:selected_ids, MapSet.new())
      |> assign(:statement_info, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user_id = socket.assigns.current_scope.user.id

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
      statement_id: params["statement_id"] || nil
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

    opts =
      case filters.filter do
        "uncategorized" -> Keyword.put(opts, :uncategorized, true)
        _ -> opts
      end

    {transactions, total} = Banking.list_transactions_paginated(user_id, opts)
    total_pages = max(1, ceil(total / @per_page))
    summary = Banking.transactions_summary(user_id, opts)
    internal_count = Enum.count(transactions, & &1.is_internal_transfer)

    statement_info =
      case filters.statement_id do
        nil ->
          nil

        id ->
          stmt = Banking.get_statement!(String.to_integer(id), user_id)
          %{id: stmt.id, filename: stmt.filename, bank: stmt.bank}
      end

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:page, page)
      |> assign(:total_pages, total_pages)
      |> assign(:total, total)
      |> assign(:transactions, transactions)
      |> assign(:editing_id, nil)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:statement_info, statement_info)
      |> assign(:summary, summary)
      |> assign(:internal_count, internal_count)

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    query_params =
      %{
        search: params["search"] || "",
        bank: params["bank"] || "all",
        statement_type: params["statement_type"] || "all",
        type: params["type"] || "all",
        category_id: params["category_id"] || "all",
        date_from: params["date_from"] || "",
        date_to: params["date_to"] || "",
        amount_min: params["amount_min"] || "",
        amount_max: params["amount_max"] || "",
        internal: params["internal"] || "all"
      }
      |> maybe_keep_statement(socket.assigns.filters)
      |> build_query_string()

    {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/transactions")}
  end

  def handle_event("clear_statement", _params, socket) do
    filters = Map.delete(socket.assigns.filters, :statement_id) |> Map.put(:statement_id, nil)
    query_params = build_query_string(filters)
    {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}
  end

  def handle_event("search", %{"search" => term}, socket) do
    filters = %{socket.assigns.filters | search: term}
    query_params = build_query_string(filters)
    {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    filters = %{socket.assigns.filters | filter: filter}
    query_params = build_query_string(filters)
    {:noreply, push_patch(socket, to: "/transactions?#{query_params}")}
  end

  def handle_event("toggle-description", %{"id" => id}, socket) do
    id = String.to_integer(id)
    expanded = socket.assigns.expanded_ids

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, :expanded_ids, expanded)}
  end

  def handle_event("edit-category", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_id, String.to_integer(id))}
  end

  def handle_event("cancel-edit", _params, socket) do
    {:noreply, assign(socket, :editing_id, nil)}
  end

  def handle_event("save-category", %{"txn_id" => id, "category_id" => category_id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    transaction = Banking.get_transaction!(String.to_integer(id), user_id)
    cat_id = String.to_integer(category_id)

    {:ok, _} = Banking.update_transaction(transaction, %{category_id: cat_id})

    description = transaction.description |> String.downcase() |> String.trim()
    Banking.create_category_rule(%{pattern: description, user_id: user_id, category_id: cat_id})

    query_params = build_query_string(socket.assigns.filters)

    socket =
      socket
      |> put_flash(:info, "Categoria atualizada e regra salva")
      |> push_patch(to: "/transactions?page=#{socket.assigns.page}&#{query_params}")

    {:noreply, socket}
  end

  def handle_event("toggle-select", %{"id" => id}, socket) do
    id = String.to_integer(id)
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
    cat_id = String.to_integer(category_id)

    {count, _} = Banking.bulk_update_categories(ids, cat_id, user_id)

    query_params = build_query_string(socket.assigns.filters)

    socket =
      socket
      |> assign(:selected_ids, MapSet.new())
      |> put_flash(:info, "#{count} transação(ões) atualizada(s)")
      |> push_patch(to: "/transactions?page=#{socket.assigns.page}&#{query_params}")

    {:noreply, socket}
  end

  def handle_event("clear-selection", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  defp maybe_keep_statement(params, %{statement_id: nil}), do: params
  defp maybe_keep_statement(params, %{statement_id: id}), do: Map.put(params, :statement_id, id)

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
          <form phx-change="apply_filters" phx-submit="apply_filters">
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
          <table class="table">
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
                <th>Data</th>
                <th>Descrição</th>
                <th>Banco</th>
                <th>Categoria</th>
                <th class="text-right">Valor</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={txn <- @transactions}
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
                  <span class="badge badge-sm badge-ghost">
                    {txn.bank_statement && String.capitalize(txn.bank_statement.bank)}
                  </span>
                </td>
                <td>
                  <form
                    :if={@editing_id == txn.id}
                    phx-change="save-category"
                    phx-click-away="cancel-edit"
                  >
                    <input type="hidden" name="txn_id" value={txn.id} />
                    <select
                      name="category_id"
                      class="select select-bordered select-xs w-auto min-w-0 max-w-36 text-xs py-0 h-6 min-h-0"
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
                  <button
                    :if={@editing_id != txn.id}
                    phx-click="edit-category"
                    phx-value-id={txn.id}
                    class="cursor-pointer"
                  >
                    <span
                      :if={txn.category}
                      class="badge badge-sm"
                      style={"background-color: #{txn.category.color}20; color: #{txn.category.color}; border-color: #{txn.category.color}40"}
                    >
                      {txn.category.name}
                    </span>
                    <span :if={!txn.category} class="badge badge-sm badge-warning">
                      Sem Categoria
                    </span>
                  </button>
                </td>
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
            patch={page_url(@filters, @page - 1)}
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-chevron-left" class="size-4" />
          </.link>
          <span :for={p <- page_range(@page, @total_pages)}>
            <.link
              :if={is_integer(p)}
              patch={page_url(@filters, p)}
              class={["btn btn-sm", (p == @page && "btn-primary") || "btn-ghost"]}
            >
              {p}
            </.link>
            <span :if={p == :dots} class="px-2 opacity-40">...</span>
          </span>
          <.link
            :if={@page < @total_pages}
            patch={page_url(@filters, @page + 1)}
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-chevron-right" class="size-4" />
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp page_url(filters, page) do
    qs = build_query_string(Map.put(filters, :page, page))
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
