defmodule GranaiWeb.StatementsLive do
  use GranaiWeb, :live_view

  alias Granai.Banking

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Extratos")
      |> assign(:delete_target, nil)
      |> assign(:selected_ids, MapSet.new())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = parse_int(params["page"], 1)
    user_id = socket.assigns.current_scope.user.id

    {statements, total} = Banking.list_statements_paginated(user_id, page: page, per_page: @per_page)
    total_pages = max(1, ceil(total / @per_page))

    socket =
      socket
      |> assign(:page, page)
      |> assign(:total_pages, total_pages)
      |> assign(:total, total)
      |> assign(:statements, statements)
      |> assign(:selected_ids, MapSet.new())

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected =
      case MapSet.member?(socket.assigns.selected_ids, id) do
        true -> MapSet.delete(socket.assigns.selected_ids, id)
        false -> MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("toggle_all", _params, socket) do
    all_ids = MapSet.new(socket.assigns.statements, & &1.id)

    selected =
      case MapSet.equal?(socket.assigns.selected_ids, all_ids) do
        true -> MapSet.new()
        false -> all_ids
      end

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    stmt = Enum.find(socket.assigns.statements, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :delete_target, {:single, stmt})}
  end

  def handle_event("confirm_bulk_delete", _params, socket) do
    count = MapSet.size(socket.assigns.selected_ids)

    case count do
      0 -> {:noreply, socket}
      _ -> {:noreply, assign(socket, :delete_target, {:bulk, count})}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_target, nil)}
  end

  def handle_event("delete", _params, socket) do
    case socket.assigns.delete_target do
      {:single, stmt} ->
        {:ok, _} = Banking.delete_statement(stmt)

        socket
        |> assign(:delete_target, nil)
        |> put_flash(:info, "Extrato removido com sucesso")
        |> reload_data()

      {:bulk, _count} ->
        ids = MapSet.to_list(socket.assigns.selected_ids)
        Banking.delete_statements(ids)

        socket
        |> assign(:delete_target, nil)
        |> assign(:selected_ids, MapSet.new())
        |> put_flash(:info, "#{length(ids)} extrato(s) removido(s)")
        |> reload_data()

      _ ->
        {:noreply, socket}
    end
  end

  defp reload_data(socket) do
    {:noreply, push_patch(socket, to: ~p"/statements?page=#{socket.assigns.page}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-8">
          <h1 class="text-3xl font-bold tracking-tight">Extratos</h1>
          <p class="text-sm opacity-60 mt-1">Gerencie seus extratos bancários importados</p>
        </div>

        <div :if={@statements == []} class="text-center py-16">
          <.icon name="hero-document-text" class="size-16 mx-auto mb-4 opacity-20" />
          <h2 class="text-xl font-semibold mb-2">Nenhum extrato encontrado</h2>
          <p class="opacity-60 mb-6">Faça upload de um extrato bancário para começar</p>
          <.link navigate={~p"/upload"} class="btn btn-primary">
            <.icon name="hero-cloud-arrow-up" class="size-5" /> Upload
          </.link>
        </div>

        <div :if={@statements != []}>
          <div :if={MapSet.size(@selected_ids) > 0} class="flex items-center gap-3 mb-4">
            <span class="text-sm opacity-60">{MapSet.size(@selected_ids)} selecionado(s)</span>
            <button phx-click="confirm_bulk_delete" class="btn btn-error btn-sm gap-1">
              <.icon name="hero-trash" class="size-4" /> Remover Selecionados
            </button>
          </div>

          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th class="w-10">
                    <input
                      type="checkbox"
                      class="checkbox checkbox-sm"
                      checked={MapSet.size(@selected_ids) == length(@statements) and length(@statements) > 0}
                      phx-click="toggle_all"
                    />
                  </th>
                  <th>Banco</th>
                  <th>Arquivo</th>
                  <th>Período</th>
                  <th>Transações</th>
                  <th>Adicionado em</th>
                  <th class="w-10"></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={stmt <- @statements} class="hover">
                  <td>
                    <input
                      type="checkbox"
                      class="checkbox checkbox-sm"
                      checked={MapSet.member?(@selected_ids, stmt.id)}
                      phx-click="toggle_select"
                      phx-value-id={stmt.id}
                    />
                  </td>
                  <td>
                    <.link navigate={~p"/transactions?statement_id=#{stmt.id}"} class="flex items-center gap-3">
                      <img src={bank_logo(stmt.bank)} alt={stmt.bank} class="w-8 h-8 rounded-full" />
                      <span class="font-medium">{String.capitalize(stmt.bank)}</span>
                    </.link>
                  </td>
                  <td>
                    <.link navigate={~p"/transactions?statement_id=#{stmt.id}"} class="hover:underline">
                      {stmt.filename}
                    </.link>
                  </td>
                  <td class="text-sm opacity-70">
                    {if stmt.period_start, do: Calendar.strftime(stmt.period_start, "%d/%m/%Y"), else: "—"}
                    a
                    {if stmt.period_end, do: Calendar.strftime(stmt.period_end, "%d/%m/%Y"), else: "—"}
                  </td>
                  <td>
                    <span class={["badge badge-sm", (stmt.status == "completed" && "badge-success") || "badge-warning"]}>
                      {stmt.total_transactions} transações
                    </span>
                  </td>
                  <td class="text-sm opacity-60">
                    {format_datetime_br(stmt.inserted_at)}
                  </td>
                  <td>
                    <button
                      phx-click="confirm_delete"
                      phx-value-id={stmt.id}
                      class="btn btn-ghost btn-xs text-error"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@total_pages > 1} class="flex justify-center gap-2 mt-6">
            <.link
              :if={@page > 1}
              patch={~p"/statements?page=#{@page - 1}"}
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-chevron-left" class="size-4" />
            </.link>
            <span :for={p <- page_range(@page, @total_pages)}>
              <.link
                :if={is_integer(p)}
                patch={~p"/statements?page=#{p}"}
                class={["btn btn-sm", (p == @page && "btn-primary") || "btn-ghost"]}
              >
                {p}
              </.link>
              <span :if={p == :dots} class="px-2 opacity-40">...</span>
            </span>
            <.link
              :if={@page < @total_pages}
              patch={~p"/statements?page=#{@page + 1}"}
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-chevron-right" class="size-4" />
            </.link>
          </div>
        </div>

        <dialog
          :if={@delete_target}
          id="delete_modal"
          class="modal modal-open"
          phx-window-keydown="cancel_delete"
          phx-key="Escape"
        >
          <div class="modal-box">
            <h3 class="text-lg font-bold">Remover extrato</h3>
            <p :if={match?({:single, _}, @delete_target)} class="py-4 opacity-70">
              Tem certeza que deseja remover o extrato
              <span class="font-semibold">{elem(@delete_target, 1).filename}</span>?
              Todas as {elem(@delete_target, 1).total_transactions} transações associadas serão removidas permanentemente.
            </p>
            <p :if={match?({:bulk, _}, @delete_target)} class="py-4 opacity-70">
              Tem certeza que deseja remover
              <span class="font-semibold">{elem(@delete_target, 1)} extratos</span>
              e todas as transações associadas? Esta ação é permanente.
            </p>
            <div class="modal-action">
              <button phx-click="cancel_delete" class="btn btn-ghost">Cancelar</button>
              <button phx-click="delete" class="btn btn-error">Remover</button>
            </div>
          </div>
          <form method="dialog" class="modal-backdrop">
            <button phx-click="cancel_delete">close</button>
          </form>
        </dialog>
      </div>
    </Layouts.app>
    """
  end

  defp format_datetime_br(dt) do
    dt
    |> DateTime.add(-3, :hour)
    |> Calendar.strftime("%d/%m/%Y %H:%M")
  end

  defp bank_logo("nubank"), do: ~p"/images/nubank-logo.png"
  defp bank_logo("bradesco"), do: ~p"/images/bradesco-logo.png"
  defp bank_logo(_), do: ~p"/images/logo-32.png"

  defp parse_int(nil, default), do: default
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n > 0 -> n
      _ -> default
    end
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
