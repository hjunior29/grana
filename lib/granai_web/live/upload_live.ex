defmodule GranaiWeb.UploadLive do
  use GranaiWeb, :live_view

  alias Granai.Banking
  alias Granai.Banking.StatementProcessor

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Upload")
      |> assign(:tab, "upload")
      |> assign(:bank, nil)
      |> assign(:statement_type, nil)
      |> assign(:processing, false)
      |> assign(:results, [])
      |> assign(:progress_current, 0)
      |> assign(:progress_total, 0)
      |> assign(:progress_filename, "")
      |> assign(:progress_ai, false)
      |> assign(:delete_target, nil)
      |> assign(:selected_ids, MapSet.new())
      |> allow_upload(:statements,
        accept: ~w(.csv .pdf),
        max_entries: 12,
        max_file_size: 5_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = params["tab"] || socket.assigns.tab
    page = parse_int(params["page"], 1)
    user_id = socket.assigns.current_scope.user.id

    {statements, total} =
      Banking.list_statements_paginated(user_id, page: page, per_page: @per_page)

    total_pages = max(1, ceil(total / @per_page))

    socket =
      socket
      |> assign(:tab, tab)
      |> assign(:page, page)
      |> assign(:total_pages, total_pages)
      |> assign(:total, total)
      |> assign(:stmt_list, statements)
      |> assign(:selected_ids, MapSet.new())

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/upload?tab=#{tab}")}
  end

  def handle_event("select-bank", %{"bank" => bank}, socket) do
    {:noreply, assign(socket, bank: bank, statement_type: nil)}
  end

  def handle_event("select-type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :statement_type, type)}
  end

  def handle_event("upload", _params, socket) do
    %{current_scope: scope} = socket.assigns
    bank = socket.assigns.bank
    statement_type = socket.assigns.statement_type

    cond do
      is_nil(bank) ->
        {:noreply, put_flash(socket, :error, "Selecione um banco antes de fazer upload")}

      is_nil(statement_type) ->
        {:noreply, put_flash(socket, :error, "Selecione o tipo (extrato ou fatura)")}

      true ->
        socket = assign(socket, :processing, true)
        send(self(), {:process_uploads, bank, statement_type, scope.user.id})
        {:noreply, socket}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :statements, ref)}
  end

  # Statement management events

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
    all_ids = MapSet.new(socket.assigns.stmt_list, & &1.id)

    selected =
      case MapSet.equal?(socket.assigns.selected_ids, all_ids) do
        true -> MapSet.new()
        false -> all_ids
      end

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    stmt = Enum.find(socket.assigns.stmt_list, &(&1.id == String.to_integer(id)))
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
        |> reload_statements()

      {:bulk, _count} ->
        ids = MapSet.to_list(socket.assigns.selected_ids)
        Banking.delete_statements(ids)

        socket
        |> assign(:delete_target, nil)
        |> assign(:selected_ids, MapSet.new())
        |> put_flash(:info, "#{length(ids)} extrato(s) removido(s)")
        |> reload_statements()

      _ ->
        {:noreply, socket}
    end
  end

  defp reload_statements(socket) do
    {:noreply, push_patch(socket, to: ~p"/upload?tab=historico&page=#{socket.assigns.page}")}
  end

  @impl true
  def handle_info({:process_uploads, bank, statement_type, user_id}, socket) do
    file_data =
      consume_uploaded_entries(socket, :statements, fn %{path: path}, entry ->
        {:ok, {entry.client_name, File.read!(path)}}
      end)

    total = length(file_data)
    parent = self()

    Task.async(fn ->
      file_data
      |> Enum.with_index(1)
      |> Enum.map(fn {{filename, content}, index} ->
        send(parent, {:processing_file, index, total, filename})

        result =
          case StatementProcessor.process(content, bank, statement_type, user_id, filename) do
            {:ok, r} -> {:ok, filename, r.transaction_count}
            {:error, reason} -> {:error, filename, reason}
          end

        send(parent, {:file_done, index, total})
        result
      end)
    end)

    {:noreply,
     assign(socket,
       upload_bank: bank,
       progress_current: 0,
       progress_total: total,
       progress_filename: ""
     )}
  end

  def handle_info({:processing_file, _index, total, filename}, socket) do
    is_ai = String.ends_with?(String.downcase(filename), ".pdf")

    {:noreply,
     assign(socket, progress_total: total, progress_filename: filename, progress_ai: is_ai)}
  end

  def handle_info({:file_done, index, total}, socket) do
    {:noreply, assign(socket, progress_current: index, progress_total: total)}
  end

  def handle_info({ref, results}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    bank = socket.assigns[:upload_bank] || ""

    {successes, errors} =
      Enum.split_with(results, fn
        {:ok, _, _} -> true
        _ -> false
      end)

    user_id = socket.assigns.current_scope.user.id
    {_stmts, total} = Banking.list_statements_paginated(user_id, page: 1, per_page: 1)

    socket =
      socket
      |> assign(:processing, false)
      |> assign(:results, successes)
      |> assign(:total, total)
      |> assign(:progress_current, 0)
      |> assign(:progress_total, 0)
      |> assign(:progress_filename, "")
      |> assign(:progress_ai, false)

    socket =
      case {successes, errors} do
        {[], errors} ->
          error_messages =
            Enum.map(errors, fn {:error, name, reason} ->
              "#{name}: #{format_error(reason, bank)}"
            end)

          put_flash(socket, :error, Enum.join(error_messages, " | "))

        {_, []} ->
          put_flash(socket, :info, "#{length(successes)} arquivo(s) processado(s) com sucesso!")

        {_, errors} ->
          error_msgs =
            Enum.map(errors, fn {:error, name, reason} ->
              "#{name}: #{format_error(reason, bank)}"
            end)

          socket
          |> put_flash(:info, "#{length(successes)} processado(s) com sucesso")
          |> put_flash(:error, Enum.join(error_msgs, " | "))
      end

    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    socket =
      socket
      |> assign(:processing, false)
      |> put_flash(:error, "Erro inesperado no processamento")

    {:noreply, socket}
  end

  defp format_error("No transactions found in file", bank) do
    "Nenhuma transação encontrada. Verifique se o arquivo é realmente do #{String.capitalize(bank)}."
  end

  defp format_error("No transactions found in PDF", bank) do
    "Nenhuma transação encontrada no PDF. Verifique se o arquivo é realmente do #{String.capitalize(bank)}."
  end

  defp format_error(reason, _bank), do: reason

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-8">
          <h1 class="text-3xl font-bold tracking-tight">Upload</h1>
          <p class="text-sm opacity-60 mt-1">Importe e gerencie seus extratos e faturas</p>
        </div>

        <div role="tablist" class="tabs tabs-border mb-8">
          <button
            role="tab"
            phx-click="switch_tab"
            phx-value-tab="upload"
            class={["tab", @tab == "upload" && "tab-active"]}
          >
            <.icon name="hero-cloud-arrow-up" class="size-4 mr-1" /> Upload
          </button>
          <button
            role="tab"
            phx-click="switch_tab"
            phx-value-tab="historico"
            class={["tab", @tab == "historico" && "tab-active"]}
          >
            <.icon name="hero-document-text" class="size-4 mr-1" />
            Histórico
            <span :if={@total > 0} class="badge badge-sm ml-1">{@total}</span>
          </button>
        </div>

        <div :if={@tab == "upload"}>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
            <button
              phx-click="select-bank"
              phx-value-bank="nubank"
              class={[
                "card bg-base-200 p-6 cursor-pointer transition-all hover:shadow-lg border-2",
                (@bank == "nubank" && "border-primary") || "border-transparent"
              ]}
            >
              <div class="flex items-center gap-4">
                <img
                  src={~p"/images/nubank-logo.png"}
                  alt="Nubank"
                  class="w-12 h-12 rounded-full"
                />
                <div class="text-left">
                  <h3 class="font-semibold text-lg">Nubank</h3>
                  <p class="text-sm opacity-70">Extrato ou fatura CSV/PDF</p>
                </div>
              </div>
            </button>

            <button
              phx-click="select-bank"
              phx-value-bank="bradesco"
              class={[
                "card bg-base-200 p-6 cursor-pointer transition-all hover:shadow-lg border-2",
                (@bank == "bradesco" && "border-primary") || "border-transparent"
              ]}
            >
              <div class="flex items-center gap-4">
                <img
                  src={~p"/images/bradesco-logo.png"}
                  alt="Bradesco"
                  class="w-12 h-12 rounded-full"
                />
                <div class="text-left">
                  <h3 class="font-semibold text-lg">Bradesco</h3>
                  <p class="text-sm opacity-70">Extrato ou fatura CSV/PDF</p>
                </div>
              </div>
            </button>
          </div>

          <div :if={@bank} class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
            <button
              phx-click="select-type"
              phx-value-type="extrato"
              class={[
                "card bg-base-200 p-5 cursor-pointer transition-all hover:shadow-lg border-2",
                (@statement_type == "extrato" && "border-info") || "border-transparent"
              ]}
            >
              <div class="flex items-center gap-3">
                <.icon name="hero-banknotes" class="size-8 text-info" />
                <div class="text-left">
                  <h3 class="font-semibold">Extrato</h3>
                  <p class="text-sm opacity-70">Conta corrente — entradas e saídas</p>
                  <p class="text-xs opacity-50 mt-1">
                    {extrato_tip(@bank)}
                  </p>
                </div>
              </div>
            </button>

            <button
              phx-click="select-type"
              phx-value-type="fatura"
              class={[
                "card bg-base-200 p-5 cursor-pointer transition-all hover:shadow-lg border-2",
                (@statement_type == "fatura" && "border-warning") || "border-transparent"
              ]}
            >
              <div class="flex items-center gap-3">
                <.icon name="hero-credit-card" class="size-8 text-warning" />
                <div class="text-left">
                  <h3 class="font-semibold">Fatura</h3>
                  <p class="text-sm opacity-70">Cartão de crédito — gastos e parcelas</p>
                  <p class="text-xs opacity-50 mt-1">
                    {fatura_tip(@bank)}
                  </p>
                </div>
              </div>
            </button>
          </div>

          <div :if={@bank && @statement_type} class="card bg-base-200 p-8 mb-8">
            <form id="upload-form" phx-submit="upload" phx-change="validate">
              <div class="flex flex-col items-center gap-4">
                <div
                  id="drop-zone"
                  class={[
                    "w-full border-2 border-dashed rounded-xl transition-all duration-200",
                    (!@processing && "border-base-content/20 hover:border-primary/50") ||
                      "border-base-content/10 opacity-50 pointer-events-none"
                  ]}
                  phx-drop-target={!@processing && @uploads.statements.ref}
                  phx-hook="DropZone"
                >
                  <.live_file_input upload={@uploads.statements} class="hidden" disabled={@processing} />
                  <label
                    for={!@processing && @uploads.statements.ref}
                    class={[
                      "block p-8 text-center",
                      (!@processing && "cursor-pointer") || "cursor-not-allowed"
                    ]}
                  >
                    <.icon name="hero-cloud-arrow-up" class="size-12 mx-auto mb-4 opacity-40" />
                    <p class="font-medium">
                      Arraste arquivos CSV ou PDF, ou clique para selecionar
                    </p>
                    <p class="text-sm opacity-60 mt-1">Até 12 arquivos, máximo 5MB cada</p>
                  </label>
                </div>

                <div :if={@uploads.statements.entries != []} class="w-full space-y-3">
                  <div
                    :for={entry <- @uploads.statements.entries}
                    class="flex items-center justify-between bg-base-100 rounded-lg p-3"
                  >
                    <div class="flex items-center gap-3">
                      <.icon name="hero-document-text" class="size-5 opacity-60" />
                      <span class="text-sm font-medium">{entry.client_name}</span>
                      <span class="badge badge-sm">{format_bytes(entry.client_size)}</span>
                    </div>
                    <button
                      type="button"
                      phx-click="cancel-upload"
                      phx-value-ref={entry.ref}
                      class="btn btn-ghost btn-xs btn-circle"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>
                </div>

                <div :for={err <- upload_errors(@uploads.statements)} class="text-error text-sm">
                  {upload_error_to_string(err)}
                </div>

                <button
                  :if={!@processing}
                  type="submit"
                  class="btn btn-primary btn-wide"
                  disabled={@uploads.statements.entries == []}
                >
                  Processar
                </button>

                <div
                  :if={@processing}
                  id="upload-progress"
                  phx-hook="ProgressBar"
                  data-progress={progress_percent(@progress_current, @progress_total)}
                  data-total={@progress_total}
                  data-ai={to_string(@progress_ai)}
                  class="w-full"
                >
                  <div class="flex items-center justify-between mb-2">
                    <div class="flex items-center gap-2">
                      <span class="loading loading-spinner loading-xs"></span>
                      <span class="text-sm">
                        <span :if={@progress_filename != ""} class="font-medium">
                          {@progress_filename}
                        </span>
                        <span :if={@progress_total > 1} class="opacity-60">
                          — {@progress_current}/{@progress_total}
                        </span>
                      </span>
                    </div>
                    <span data-pct class="text-sm font-mono opacity-60">0%</span>
                  </div>
                  <progress class="progress progress-primary w-full" value="0" max="100">
                  </progress>
                </div>
              </div>
            </form>
          </div>
        </div>

        <div :if={@tab == "historico"}>
          <div :if={@stmt_list == []} class="text-center py-16">
            <.icon name="hero-document-text" class="size-16 mx-auto mb-4 opacity-20" />
            <h2 class="text-xl font-semibold mb-2">Nenhum extrato encontrado</h2>
            <p class="opacity-60 mb-6">Faça upload de um extrato bancário para começar</p>
            <button phx-click="switch_tab" phx-value-tab="upload" class="btn btn-primary">
              <.icon name="hero-cloud-arrow-up" class="size-5" /> Upload
            </button>
          </div>

          <div :if={@stmt_list != []}>
            <div :if={MapSet.size(@selected_ids) > 0} class="flex items-center gap-3 mb-4">
              <span class="text-sm opacity-60">
                {MapSet.size(@selected_ids)} selecionado(s)
              </span>
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
                        checked={
                          MapSet.size(@selected_ids) == length(@stmt_list) and
                            length(@stmt_list) > 0
                        }
                        phx-click="toggle_all"
                      />
                    </th>
                    <th>Banco</th>
                    <th>Tipo</th>
                    <th>Arquivo</th>
                    <th>Período</th>
                    <th>Transações</th>
                    <th>Adicionado em</th>
                    <th class="w-10"></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={stmt <- @stmt_list} class="hover">
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
                      <.link
                        navigate={~p"/transactions?statement_id=#{stmt.id}"}
                        class="flex items-center gap-3"
                      >
                        <img
                          src={bank_logo(stmt.bank)}
                          alt={stmt.bank}
                          class="w-8 h-8 rounded-full"
                        />
                        <span class="font-medium">{String.capitalize(stmt.bank)}</span>
                      </.link>
                    </td>
                    <td>
                      <span class={["badge badge-sm", type_badge_class(stmt.statement_type)]}>
                        {type_label(stmt.statement_type)}
                      </span>
                    </td>
                    <td>
                      <.link
                        navigate={~p"/transactions?statement_id=#{stmt.id}"}
                        class="hover:underline"
                      >
                        {stmt.filename}
                      </.link>
                    </td>
                    <td class="text-sm opacity-70">
                      {if stmt.period_start,
                        do: Calendar.strftime(stmt.period_start, "%d/%m/%Y"),
                        else: "—"} a {if stmt.period_end,
                        do: Calendar.strftime(stmt.period_end, "%d/%m/%Y"),
                        else: "—"}
                    </td>
                    <td>
                      <span class={[
                        "badge badge-sm whitespace-nowrap",
                        (stmt.status == "completed" && "badge-success") || "badge-warning"
                      ]}>
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
                patch={~p"/upload?tab=historico&page=#{@page - 1}"}
                class="btn btn-sm btn-ghost"
              >
                <.icon name="hero-chevron-left" class="size-4" />
              </.link>
              <span :for={p <- page_range(@page, @total_pages)}>
                <.link
                  :if={is_integer(p)}
                  patch={~p"/upload?tab=historico&page=#{p}"}
                  class={["btn btn-sm", (p == @page && "btn-primary") || "btn-ghost"]}
                >
                  {p}
                </.link>
                <span :if={p == :dots} class="px-2 opacity-40">...</span>
              </span>
              <.link
                :if={@page < @total_pages}
                patch={~p"/upload?tab=historico&page=#{@page + 1}"}
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
                Todas as {elem(@delete_target, 1).total_transactions}
                transações associadas serão removidas permanentemente.
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
      </div>
    </Layouts.app>
    """
  end

  defp progress_percent(_current, 0), do: 0
  defp progress_percent(current, total), do: round(current / total * 100)

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  defp upload_error_to_string(:too_large), do: "Arquivo muito grande (máximo 5MB)"
  defp upload_error_to_string(:not_accepted), do: "Tipo de arquivo não aceito (use CSV ou PDF)"
  defp upload_error_to_string(:too_many_files), do: "Muitos arquivos (máximo 12)"
  defp upload_error_to_string(err), do: "Erro: #{inspect(err)}"

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

  defp extrato_tip("nubank"), do: "Recomendado: CSV"
  defp extrato_tip("bradesco"), do: "Recomendado: PDF"
  defp extrato_tip(_), do: ""

  defp fatura_tip("nubank"), do: "Recomendado: CSV"
  defp fatura_tip("bradesco"), do: "Recomendado: CSV"
  defp fatura_tip(_), do: ""

  defp type_badge_class("fatura"), do: "badge-warning"
  defp type_badge_class(_), do: "badge-info"

  defp type_label("fatura"), do: "Fatura"
  defp type_label(_), do: "Extrato"
end
