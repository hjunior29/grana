defmodule GranaWeb.UploadLive do
  use GranaWeb, :live_view

  alias Grana.Banking

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Upload")
      |> assign(:tab, "upload")
      |> assign(:upload_category, nil)
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
      |> assign(:cal_rows, [])
      |> assign(:cal_has_data, false)
      |> assign(:cal_score, nil)
      |> assign(:show_api_key_alert, false)
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

    page_stmts = Enum.map(statements, &normalize_banking_stmt/1)
    total_pages = max(1, ceil(total / @per_page))

    socket =
      socket
      |> assign(:tab, tab)
      |> assign(:page, page)
      |> assign(:total_pages, total_pages)
      |> assign(:total, total)
      |> assign(:stmt_list, page_stmts)
      |> assign(:selected_ids, MapSet.new())
      |> maybe_load_calendar(tab, user_id)

    {:noreply, socket}
  end

  # Calendário de importações: só carrega os dados quando a sub-aba está ativa.
  defp maybe_load_calendar(socket, "calendario", user_id) do
    bank = Banking.coverage_by_statement_type(user_id)
    upload_counts = Banking.upload_counts_by_month(user_id)

    build_calendar_grid(socket, bank["extrato"], bank["fatura"], upload_counts)
  end

  defp maybe_load_calendar(socket, _tab, _user_id), do: socket

  defp normalize_banking_stmt(stmt) do
    %{
      composite_id: "bank_#{stmt.id}",
      raw_id: stmt.id,
      source: "banking",
      name: String.capitalize(stmt.bank),
      logo: bank_logo(stmt.bank),
      type_label: type_label(stmt.statement_type),
      type_badge: type_badge_class(stmt.statement_type),
      filename: stmt.filename,
      period_start: stmt.period_start,
      period_end: stmt.period_end,
      total_transactions: stmt.total_transactions,
      inserted_at: stmt.inserted_at,
      status: stmt.status,
      link: ~p"/transactions?statement_id=#{stmt.id}"
    }
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("switch_tab", _params, %{assigns: %{processing: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/upload?tab=#{tab}")}
  end

  def handle_event("select-bank", _params, %{assigns: %{processing: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("select-bank", %{"bank" => bank}, socket) do
    # Cancel any existing uploads when switching bank
    socket =
      Enum.reduce(socket.assigns.uploads.statements.entries, socket, fn entry, acc ->
        cancel_upload(acc, :statements, entry.ref)
      end)

    accept = if bank == "outro", do: ~w(.pdf), else: ~w(.csv .pdf)

    socket =
      socket
      |> assign(bank: bank, statement_type: nil)
      |> allow_upload(:statements,
        accept: accept,
        max_entries: 12,
        max_file_size: 5_000_000
      )

    {:noreply, socket}
  end

  def handle_event("select-type", _params, %{assigns: %{processing: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("select-type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :statement_type, type)}
  end

  # Upload category selection (banking vs platform)

  def handle_event("select_upload_category", _params, %{assigns: %{processing: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("select_upload_category", %{"category" => "banking"}, socket) do
    socket =
      socket
      |> assign(:upload_category, "banking")
      |> assign(:bank, nil)
      |> assign(:statement_type, nil)
      |> cancel_all_uploads()
      |> allow_upload(:statements,
        accept: ~w(.csv .pdf),
        max_entries: 12,
        max_file_size: 5_000_000
      )

    {:noreply, socket}
  end

  def handle_event("select_upload_category", %{"category" => "platform"}, socket) do
    socket =
      socket
      |> assign(:upload_category, "platform")
      |> assign(:bank, nil)
      |> assign(:statement_type, nil)
      |> cancel_all_uploads()
      |> allow_upload(:statements,
        accept: ~w(.csv),
        max_entries: 12,
        max_file_size: 5_000_000
      )

    {:noreply, socket}
  end

  def handle_event("upload", _params, socket) do
    case socket.assigns.upload_category do
      "platform" -> handle_platform_upload(socket)
      _ -> handle_banking_upload(socket)
    end
  end

  def handle_event("dismiss_api_alert", _params, socket) do
    {:noreply, assign(socket, :show_api_key_alert, false)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :statements, ref)}
  end

  # Statement management events

  def handle_event("toggle_select", %{"id" => composite_id}, socket) do
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, composite_id),
        do: MapSet.delete(selected, composite_id),
        else: MapSet.put(selected, composite_id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("toggle_all", _params, socket) do
    all_ids = MapSet.new(socket.assigns.stmt_list, & &1.composite_id)

    selected =
      if MapSet.equal?(socket.assigns.selected_ids, all_ids),
        do: MapSet.new(),
        else: all_ids

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("confirm_delete", %{"id" => composite_id}, socket) do
    stmt = Enum.find(socket.assigns.stmt_list, &(&1.composite_id == composite_id))
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
    user_id = socket.assigns.current_scope.user.id

    case socket.assigns.delete_target do
      {:single, stmt} ->
        bank_stmt = Banking.get_statement!(stmt.raw_id, user_id)
        Banking.delete_statement(bank_stmt)
        # Sem esse upload, o Open Finance volta a cobrir o período.
        Grana.OpenFinance.uploads_changed(user_id)

        socket
        |> assign(:delete_target, nil)
        |> put_flash(:info, "Extrato removido com sucesso")
        |> reload_statements()

      {:bulk, _count} ->
        ids =
          socket.assigns.selected_ids
          |> MapSet.to_list()
          |> Enum.flat_map(fn
            "bank_" <> raw ->
              case Integer.parse(raw) do
                {n, ""} -> [n]
                _ -> []
              end

            _ ->
              []
          end)

        if ids != [] do
          Banking.delete_statements(ids, user_id)
          Grana.OpenFinance.uploads_changed(user_id)
        end

        socket
        |> assign(:delete_target, nil)
        |> assign(:selected_ids, MapSet.new())
        |> put_flash(:info, "#{length(ids)} extrato(s) removido(s)")
        |> reload_statements()

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_banking_upload(socket) do
    %{current_scope: scope} = socket.assigns
    bank = socket.assigns.bank
    statement_type = socket.assigns.statement_type

    has_pdf =
      Enum.any?(socket.assigns.uploads.statements.entries, fn entry ->
        String.ends_with?(String.downcase(entry.client_name), ".pdf")
      end)

    needs_api_key = (has_pdf and not deterministic_pdf?(bank, statement_type)) or bank == "outro"

    cond do
      is_nil(bank) ->
        {:noreply, put_flash(socket, :error, "Selecione um banco antes de fazer upload")}

      is_nil(statement_type) ->
        {:noreply, put_flash(socket, :error, "Selecione o tipo (extrato ou fatura)")}

      needs_api_key ->
        case Grana.Accounts.get_user_ai_config(scope.user.id) do
          {:error, :no_api_key} ->
            {:noreply, assign(socket, :show_api_key_alert, true)}

          {:ok, _config} ->
            socket = assign(socket, :processing, true)
            send(self(), {:process_uploads, bank, statement_type, scope.user.id})
            {:noreply, socket}
        end

      true ->
        socket = assign(socket, :processing, true)
        send(self(), {:process_uploads, bank, statement_type, scope.user.id})
        {:noreply, socket}
    end
  end

  # PDFs que conseguimos extrair de forma determinística (pdftotext) não exigem
  # API key. A IA só entra como fallback (PDF escaneado / sem camada de texto).
  defp deterministic_pdf?("bradesco", "extrato"), do: true
  defp deterministic_pdf?(_bank, _statement_type), do: false

  defp handle_platform_upload(socket) do
    scope = socket.assigns.current_scope
    socket = assign(socket, :processing, true)
    send(self(), {:process_platform_uploads, scope.user.id})
    {:noreply, socket}
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
    topic = "upload:#{user_id}:#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Grana.PubSub, topic)

    files =
      Enum.map(file_data, fn {filename, content} ->
        %{"filename" => filename, "content_b64" => Base.encode64(content)}
      end)

    %{
      files: files,
      bank: bank,
      statement_type: statement_type,
      user_id: user_id,
      topic: topic
    }
    |> Grana.Workers.StatementUploadWorker.new()
    |> Oban.insert()

    {:noreply,
     assign(socket,
       upload_bank: bank,
       progress_current: 0,
       progress_total: total,
       progress_filename: ""
     )}
  end

  def handle_info({:process_platform_uploads, user_id}, socket) do
    file_data =
      consume_uploaded_entries(socket, :statements, fn %{path: path}, entry ->
        {:ok, {entry.client_name, File.read!(path)}}
      end)

    total = length(file_data)
    topic = "upload:#{user_id}:#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Grana.PubSub, topic)

    files =
      Enum.map(file_data, fn {filename, content} ->
        %{"filename" => filename, "content_b64" => Base.encode64(content)}
      end)

    %{files: files, user_id: user_id, topic: topic}
    |> Grana.Workers.PlatformImportWorker.new()
    |> Oban.insert()

    {:noreply,
     assign(socket,
       upload_bank: "grana",
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

  def handle_info({:upload_complete, results}, socket) do
    bank = socket.assigns[:upload_bank] || ""

    {successes, errors} =
      Enum.split_with(results, fn
        {:ok, _, _, _} -> true
        {:ok, _, _} -> true
        _ -> false
      end)

    socket =
      socket
      |> assign(:processing, false)
      |> assign(:results, successes)
      |> assign(:progress_current, 0)
      |> assign(:progress_total, 0)
      |> assign(:progress_filename, "")
      |> assign(:progress_ai, false)

    # Collect parser warnings from successful results
    all_warnings =
      successes
      |> Enum.flat_map(fn
        {:ok, filename, _count, warnings} when warnings != [] ->
          Enum.map(warnings, &"#{filename}: #{&1}")

        _ ->
          []
      end)

    socket =
      case {successes, errors} do
        {[], errors} ->
          put_flash(socket, :error, build_error_message(errors, bank))

        {_, []} ->
          put_flash(socket, :info, "#{length(successes)} arquivo(s) processado(s) com sucesso!")

        {_, errors} ->
          socket
          |> put_flash(:info, "#{length(successes)} processado(s) com sucesso")
          |> put_flash(:error, build_error_message(errors, bank))
      end

    socket =
      if all_warnings != [] do
        warning_count = length(all_warnings)
        summary = Enum.take(all_warnings, 5) |> Enum.join(" | ")
        extra = if warning_count > 5, do: " (+#{warning_count - 5} mais)", else: ""
        put_flash(socket, :warning, "#{warning_count} linha(s) ignorada(s): #{summary}#{extra}")
      else
        socket
      end

    {:noreply, push_patch(socket, to: ~p"/upload?tab=#{socket.assigns.tab}&page=1")}
  end

  # Limita a 5 erros exibidos (+N mais) para a flash não crescer sem limite.
  defp build_error_message(errors, bank) do
    shown = Enum.take(errors, 5)

    msgs =
      Enum.map(shown, fn {:error, name, reason} -> "#{name}: #{format_error(reason, bank)}" end)

    extra = length(errors) - length(shown)
    base = Enum.join(msgs, " | ")
    if extra > 0, do: base <> " (+#{extra} mais)", else: base
  end

  defp format_error("No transactions found in file", "outro") do
    "Nenhuma transação encontrada no arquivo."
  end

  defp format_error("No transactions found in file", bank) do
    "Nenhuma transação encontrada. Verifique se o arquivo é realmente do #{String.capitalize(bank)}."
  end

  defp format_error("No transactions found in PDF", "outro") do
    "Nenhuma transação encontrada no PDF."
  end

  defp format_error("No transactions found in PDF", bank) do
    "Nenhuma transação encontrada no PDF. Verifique se o arquivo é realmente do #{String.capitalize(bank)}."
  end

  defp format_error(:no_api_key, _bank) do
    "Não foi possível extrair o PDF automaticamente (pode ser digitalizado). " <>
      "Configure uma API Key do Gemini nas Configurações para processá-lo via IA."
  end

  defp format_error(reason, _bank) when is_binary(reason), do: reason
  # Nunca expõe termos internos crus (tuplas/atoms) ao usuário.
  defp format_error(_reason, _bank), do: "Não foi possível processar o arquivo."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto scrollbar-gutter">
        <div class="mb-4 sm:mb-8 text-center sm:text-left">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Upload</h1>
          <p class="text-xs sm:text-sm opacity-60 mt-1">
            Importe e gerencie seus extratos e faturas
          </p>
        </div>

        <div role="tablist" class="tabs tabs-border mb-8">
          <button
            role="tab"
            phx-click="switch_tab"
            phx-value-tab="upload"
            disabled={@processing}
            class={[
              "tab",
              @tab == "upload" && "tab-active",
              @processing && "opacity-50 cursor-not-allowed"
            ]}
          >
            <.icon name="hero-cloud-arrow-up" class="size-4 mr-1" /> Upload
          </button>
          <button
            role="tab"
            phx-click="switch_tab"
            phx-value-tab="historico"
            disabled={@processing}
            class={[
              "tab",
              @tab == "historico" && "tab-active",
              @processing && "opacity-50 cursor-not-allowed"
            ]}
          >
            <.icon name="hero-document-text" class="size-4 mr-1" /> Histórico
            <span :if={@total > 0} class="badge badge-sm badge-ghost ml-1">{@total}</span>
          </button>
          <button
            role="tab"
            phx-click="switch_tab"
            phx-value-tab="calendario"
            disabled={@processing}
            class={[
              "tab",
              @tab == "calendario" && "tab-active",
              @processing && "opacity-50 cursor-not-allowed"
            ]}
          >
            <.icon name="hero-calendar-days" class="size-4 mr-1" /> Calendário
          </button>
        </div>

        <div :if={@tab == "upload"}>
          <%!-- Upload Category Selection --%>
          <div class={[
            "grid grid-cols-1 md:grid-cols-2 gap-4 mb-8",
            @processing && "opacity-50 pointer-events-none"
          ]}>
            <button
              phx-click="select_upload_category"
              phx-value-category="banking"
              disabled={@processing}
              class={[
                "card bg-base-200 p-6 cursor-pointer transition-all hover:shadow-lg border-2",
                (@upload_category == "banking" && "border-primary") || "border-transparent"
              ]}
            >
              <div class="flex items-center gap-4">
                <div class="w-12 h-12 rounded-full bg-base-300 flex items-center justify-center">
                  <.icon name="hero-banknotes" class="size-6 text-info" />
                </div>
                <div class="text-left">
                  <h3 class="font-semibold text-lg">Fatura / Extrato</h3>
                  <p class="text-sm opacity-70">Conta corrente e cartão de crédito</p>
                </div>
              </div>
            </button>

            <button
              phx-click="select_upload_category"
              phx-value-category="platform"
              disabled={@processing}
              class={[
                "card bg-base-200 p-6 cursor-pointer transition-all hover:shadow-lg border-2",
                (@upload_category == "platform" && "border-primary") || "border-transparent"
              ]}
            >
              <div class="flex items-center gap-4">
                <div class="w-12 h-12 rounded-full bg-base-300 flex items-center justify-center">
                  <.icon name="hero-arrow-up-tray" class="size-6 text-secondary" />
                </div>
                <div class="text-left">
                  <h3 class="font-semibold text-lg">Grana (exportação)</h3>
                  <p class="text-sm opacity-70">Reimporte um CSV exportado da plataforma</p>
                </div>
              </div>
            </button>
          </div>

          <div :if={@upload_category == "banking"}>
            <div class={[
              "grid grid-cols-1 md:grid-cols-3 gap-6 mb-8",
              @processing && "opacity-50 pointer-events-none"
            ]}>
              <button
                phx-click="select-bank"
                phx-value-bank="nubank"
                disabled={@processing}
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
                disabled={@processing}
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

              <button
                phx-click="select-bank"
                phx-value-bank="outro"
                disabled={@processing}
                class={[
                  "card bg-base-200 p-6 cursor-pointer transition-all hover:shadow-lg border-2",
                  (@bank == "outro" && "border-primary") || "border-transparent"
                ]}
              >
                <div class="flex items-center gap-4">
                  <div class="w-12 h-12 rounded-full bg-base-300 flex items-center justify-center">
                    <.icon name="hero-building-library" class="size-6 opacity-60" />
                  </div>
                  <div class="text-left">
                    <h3 class="font-semibold text-lg">Outro banco</h3>
                    <p class="text-sm opacity-70">Qualquer banco via PDF + IA</p>
                  </div>
                </div>
              </button>
            </div>

            <div
              :if={@bank}
              class={[
                "grid grid-cols-1 md:grid-cols-2 gap-4 mb-8",
                @processing && "opacity-50 pointer-events-none"
              ]}
            >
              <button
                phx-click="select-type"
                phx-value-type="extrato"
                disabled={@processing}
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
                disabled={@processing}
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
                    <.live_file_input
                      upload={@uploads.statements}
                      class="hidden"
                      disabled={@processing}
                    />
                    <label
                      for={!@processing && @uploads.statements.ref}
                      class={[
                        "block p-8 text-center",
                        (!@processing && "cursor-pointer") || "cursor-not-allowed"
                      ]}
                    >
                      <.icon name="hero-cloud-arrow-up" class="size-12 mx-auto mb-4 opacity-40" />
                      <p class="font-medium">
                        <%= if @bank == "outro" do %>
                          Arraste arquivos PDF, ou clique para selecionar
                        <% else %>
                          Arraste arquivos CSV ou PDF, ou clique para selecionar
                        <% end %>
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
                    <progress class="progress progress-primary w-full" value="0" max="100"></progress>
                  </div>
                </div>
              </form>
            </div>
          </div>

          <%!-- Platform export re-import --%>
          <div :if={@upload_category == "platform"}>
            <div class="card bg-base-200 p-8 mb-8">
              <p class="text-sm opacity-70 mb-4">
                Envie um ou mais CSVs exportados pelo próprio Grana (de transações bancárias).
                O banco/origem e as categorias são detectados e recriados automaticamente; reimportar não duplica.
              </p>
              <form id="upload-form-platform" phx-submit="upload" phx-change="validate">
                <div class="flex flex-col items-center gap-4">
                  <div
                    id="drop-zone-platform"
                    class={[
                      "w-full border-2 border-dashed rounded-xl transition-all duration-200",
                      (!@processing && "border-base-content/20 hover:border-primary/50") ||
                        "border-base-content/10 opacity-50 pointer-events-none"
                    ]}
                    phx-drop-target={!@processing && @uploads.statements.ref}
                    phx-hook="DropZone"
                  >
                    <.live_file_input
                      upload={@uploads.statements}
                      class="hidden"
                      disabled={@processing}
                    />
                    <label
                      for={!@processing && @uploads.statements.ref}
                      class={[
                        "block p-8 text-center",
                        (!@processing && "cursor-pointer") || "cursor-not-allowed"
                      ]}
                    >
                      <.icon name="hero-cloud-arrow-up" class="size-12 mx-auto mb-4 opacity-40" />
                      <p class="font-medium">
                        Arraste CSVs exportados do Grana, ou clique para selecionar
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
                    Importar
                  </button>

                  <div
                    :if={@processing}
                    id="upload-progress-platform"
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
                    <progress class="progress progress-primary w-full" value="0" max="100"></progress>
                  </div>
                </div>
              </form>
            </div>
          </div>
        </div>

        <div :if={@tab == "historico"}>
          <div class="flex items-center justify-between mb-4">
            <span class="text-sm opacity-50">{@total} extrato(s)</span>
          </div>

          <div :if={@stmt_list == []} class="text-center py-16">
            <.icon name="hero-document-text" class="size-16 mx-auto mb-4 opacity-20" />
            <h2 class="text-xl font-semibold mb-2">Nenhum extrato encontrado</h2>
            <p class="opacity-60 mb-6">Faça upload de um extrato para começar</p>
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
                    <th>Origem</th>
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
                        checked={MapSet.member?(@selected_ids, stmt.composite_id)}
                        phx-click="toggle_select"
                        phx-value-id={stmt.composite_id}
                      />
                    </td>
                    <td>
                      <.link navigate={stmt.link} class="flex items-center gap-3">
                        <div
                          :if={stmt.logo}
                          class="w-8 h-8 rounded-full overflow-hidden bg-base-300 shrink-0"
                        >
                          <img src={stmt.logo} alt={stmt.name} />
                        </div>
                        <div
                          :if={!stmt.logo}
                          class="w-8 h-8 rounded-full bg-base-300 flex items-center justify-center"
                        >
                          <.icon name="hero-building-library" class="size-4 opacity-60" />
                        </div>
                        <span class="font-medium">{stmt.name}</span>
                      </.link>
                    </td>
                    <td>
                      <span class={["badge badge-sm", stmt.type_badge]}>
                        {stmt.type_label}
                      </span>
                    </td>
                    <td>
                      <.link navigate={stmt.link} class="hover:underline">
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
                        phx-value-id={stmt.composite_id}
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
                Tem certeza que deseja remover o extrato <span class="font-semibold">{elem(@delete_target, 1).filename}</span>?
                Todas as {elem(@delete_target, 1).total_transactions} transações associadas serão removidas permanentemente.
              </p>
              <p :if={match?({:bulk, _}, @delete_target)} class="py-4 opacity-70">
                Tem certeza que deseja remover
                <span class="font-semibold">{elem(@delete_target, 1)} extrato(s)</span>
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

        <div :if={@tab == "calendario"}>
          <div class="mb-6">
            <h2 class="text-lg font-semibold">Calendário de Importações</h2>
            <p class="text-xs sm:text-sm opacity-60 mt-1">
              Cada quadrado é um mês. Quanto mais intenso, mais tipos de documento (extrato ou
              fatura) você importou naquele mês. Passe o mouse para ver os detalhes.
            </p>
          </div>

          <div :if={!@cal_has_data} class="text-center py-16 opacity-60">
            <.icon name="hero-calendar-days" class="size-10 mx-auto mb-3 opacity-40" />
            <p>Ainda não há dados importados.</p>
            <p class="text-sm mt-1">
              Importe extratos ou faturas na aba <button
                type="button"
                phx-click="switch_tab"
                phx-value-tab="upload"
                class="link"
              >
                Upload
              </button>.
            </p>
          </div>

          <div :if={@cal_has_data} class="grana-calendar-card card bg-base-200 w-full">
            <div class="card-body p-5 sm:p-8">
              <div class="flex flex-col lg:flex-row gap-6 lg:gap-8 lg:items-center">
                <div class="flex-1 min-w-0">
                  <div
                    id="calendar-heatmap"
                    phx-hook="CalendarHeatmap"
                    phx-update="ignore"
                    class="grana-calendar-heatmap w-full"
                  >
                    <%!-- Cabeçalho de meses --%>
                    <div class="flex gap-1 sm:gap-1.5 mb-2">
                      <div class="w-8 sm:w-12 shrink-0"></div>
                      <div
                        :for={m <- 1..12}
                        class="grana-calendar-month-label flex-1 min-w-0 text-center text-[10px] sm:text-sm font-medium"
                      >
                        {month_label(m)}
                      </div>
                    </div>

                    <%!-- Linhas por ano. Sem rolagem: as células usam flex-1/aspect-square
                          para caber na largura, e o card cresce pra baixo a cada ano. --%>
                    <div
                      :for={row <- @cal_rows}
                      class="flex gap-1 sm:gap-1.5 items-center mb-1 sm:mb-1.5"
                    >
                      <div class="grana-calendar-year-label w-8 sm:w-12 shrink-0 text-right pr-1 text-xs sm:text-sm font-medium">
                        {row.year}
                      </div>
                      <div
                        :for={cell <- row.cells}
                        class={[
                          "grana-calendar-cell flex-1 min-w-0 aspect-square transition duration-150",
                          cell_hover_class(cell),
                          cell_class(cell)
                        ]}
                        aria-label={cell_title(cell)}
                        data-calendar-month={cell_month(cell)}
                        data-calendar-uploads={cell_uploads(cell)}
                        data-calendar-types={cell_types(cell)}
                        data-calendar-count={cell_upload_count(cell)}
                      >
                      </div>
                    </div>
                  </div>

                  <%!-- Legenda --%>
                  <div class="grana-calendar-legend flex flex-wrap items-center justify-center gap-2 mt-6 text-sm">
                    <span class="mr-1">Menos</span>
                    <div
                      class="grana-calendar-legend-swatch calendar-count-0"
                      title="nenhum tipo"
                    >
                    </div>
                    <div
                      class="grana-calendar-legend-swatch calendar-count-1"
                      title="1 tipo"
                    >
                    </div>
                    <div
                      class="grana-calendar-legend-swatch calendar-count-3"
                      title="2 tipos"
                    >
                    </div>
                    <span class="ml-1">Mais</span>
                    <span class="ml-3 opacity-70">
                      Tom cheio = extrato + fatura no mês.
                    </span>
                  </div>
                </div>

                <%!-- Pontuação de cobertura (donut), no mesmo card --%>
                <div class="grana-calendar-score flex flex-col items-center text-center gap-1 shrink-0 lg:w-64 lg:border-l lg:border-base-content/10 lg:pl-8">
                  <h3 class="text-sm font-semibold opacity-70">Cobertura de importações</h3>
                  <div class="relative">
                    <svg
                      viewBox="0 0 120 120"
                      class="w-44 h-44 sm:w-52 sm:h-52 -rotate-90 overflow-visible"
                    >
                      <circle
                        cx="60"
                        cy="60"
                        r="52"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="11"
                        class="grana-calendar-score-track"
                      />
                      <circle
                        cx="60"
                        cy="60"
                        r="52"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="11"
                        stroke-linecap="round"
                        stroke-dasharray={@cal_score.circumference}
                        stroke-dashoffset={@cal_score.dashoffset}
                        class={[
                          "grana-calendar-score-ring transition-all duration-700 ease-out",
                          @cal_score.color_class
                        ]}
                      />
                    </svg>
                    <div class="absolute inset-0 flex items-center justify-center">
                      <span class="text-4xl font-bold">{@cal_score.pct}%</span>
                    </div>
                  </div>
                  <p class="text-base font-medium mt-1">{@cal_score.label}</p>
                  <p class="text-xs opacity-50">
                    {@cal_score.imports} de {@cal_score.ideal} importações
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
        <dialog
          :if={@show_api_key_alert}
          class="modal modal-open"
          phx-window-keydown="dismiss_api_alert"
          phx-key="Escape"
        >
          <div class="modal-box">
            <h3 class="text-lg font-bold">API Key não configurada</h3>
            <p class="py-4 opacity-70">
              Para processar arquivos PDF, é necessário configurar uma API Key do Google Gemini. A IA é usada para extrair as transações do PDF.
            </p>
            <ol class="list-decimal list-inside text-sm opacity-70 space-y-1 mb-4">
              <li>
                Acesse
                <a href="https://aistudio.google.com/apikey" target="_blank" class="link link-primary">
                  Google AI Studio
                </a>
              </li>
              <li>Crie uma API Key gratuita</li>
              <li>Cole a chave nas Configurações</li>
            </ol>
            <div class="modal-action">
              <button phx-click="dismiss_api_alert" class="btn btn-ghost">Fechar</button>
              <.link navigate={~p"/users/settings"} class="btn btn-primary">
                Ir para Configurações
              </.link>
            </div>
          </div>
          <form method="dialog" class="modal-backdrop">
            <button phx-click="dismiss_api_alert">close</button>
          </form>
        </dialog>
      </div>
    </Layouts.app>
    """
  end

  # ── Calendário de importações (heatmap ano × mês) ──

  defp build_calendar_grid(socket, extrato, fatura, upload_counts) do
    all = MapSet.union(extrato, fatura)

    if MapSet.size(all) == 0 do
      assign(socket, cal_rows: [], cal_has_data: false, cal_score: nil)
    else
      today = Date.utc_today()
      start_year = all |> Enum.map(&elem(&1, 0)) |> Enum.min()

      rows =
        for year <- start_year..today.year do
          cells =
            for month <- 1..12 do
              ym = {year, month}

              labels =
                [
                  {"Extrato", MapSet.member?(extrato, ym)},
                  {"Fatura", MapSet.member?(fatura, ym)}
                ]
                |> Enum.filter(&elem(&1, 1))
                |> Enum.map(&elem(&1, 0))

              %{
                month: month,
                year: year,
                count: length(labels),
                upload_count: Map.get(upload_counts, ym, 0),
                labels: labels,
                future?: year > today.year or (year == today.year and month > today.month)
              }
            end

          %{year: year, cells: cells}
        end

      # Pontuação: o ideal é 2 imports por mês (extrato + fatura),
      # contados do 1º import até o mês atual → ideal = meses × 2. O total do
      # usuário soma, por mês, no máximo 2 imports (mês com mais de 2 vale 2).
      {first_y, first_m} = Enum.min(all)
      first_index = first_y * 12 + first_m
      now_index = today.year * 12 + today.month
      ideal = (now_index - first_index + 1) * 2

      imports =
        Enum.reduce(upload_counts, 0, fn {{y, m}, cnt}, acc ->
          idx = y * 12 + m
          if idx >= first_index and idx <= now_index, do: acc + min(cnt, 2), else: acc
        end)

      pct = if ideal > 0, do: min(100, round(imports / ideal * 100)), else: 0
      circumference = 2 * :math.pi() * 52

      score = %{
        pct: pct,
        imports: imports,
        ideal: ideal,
        color_class: score_color_class(pct),
        label: score_label(pct),
        circumference: Float.round(circumference, 2),
        dashoffset: Float.round(circumference * (1 - pct / 100), 2)
      }

      assign(socket, cal_rows: rows, cal_has_data: true, cal_score: score)
    end
  end

  defp score_color_class(pct) when pct >= 80, do: "calendar-count-3"
  defp score_color_class(pct) when pct >= 40, do: "calendar-count-2"
  defp score_color_class(_pct), do: "calendar-count-1"

  defp score_label(100), do: "Histórico completo!"
  defp score_label(pct) when pct >= 80, do: "Quase tudo importado"
  defp score_label(pct) when pct >= 50, do: "Bom histórico"
  defp score_label(pct) when pct >= 25, do: "Faltam vários meses"
  defp score_label(_pct), do: "Histórico bem incompleto"

  defp pluralize_uploads(1), do: "1 upload"
  defp pluralize_uploads(count), do: "#{count} uploads"

  defp cell_class(%{future?: true}), do: "calendar-count-future opacity-60"
  defp cell_class(%{count: 0}), do: "calendar-count-0 cursor-pointer"
  defp cell_class(%{count: 1}), do: "calendar-count-1 cursor-pointer"
  defp cell_class(%{count: 2}), do: "calendar-count-3 cursor-pointer"

  defp cell_hover_class(%{future?: true}), do: "pointer-events-none"

  defp cell_hover_class(_cell),
    do: "hover:-translate-y-0.5 hover:scale-105 hover:brightness-110"

  defp cell_title(%{future?: true}), do: nil

  defp cell_title(%{month: m, year: y, labels: [], upload_count: upload_count}),
    do: "#{month_label(m)}/#{y} - #{pluralize_uploads(upload_count)} - sem dados"

  defp cell_title(%{month: m, year: y, labels: labels, upload_count: upload_count}),
    do: "#{month_label(m)}/#{y} - #{pluralize_uploads(upload_count)} - #{Enum.join(labels, ", ")}"

  defp cell_month(%{future?: true}), do: nil
  defp cell_month(%{month: m, year: y}), do: "#{month_label(m)}/#{y}"

  defp cell_uploads(%{future?: true}), do: nil
  defp cell_uploads(%{upload_count: upload_count}), do: pluralize_uploads(upload_count)

  defp cell_upload_count(%{future?: true}), do: nil
  defp cell_upload_count(%{upload_count: upload_count}), do: upload_count

  defp cell_types(%{future?: true}), do: nil
  defp cell_types(%{labels: []}), do: "Sem dados"
  defp cell_types(%{labels: labels}), do: Enum.join(labels, ", ")

  @month_abbr {"Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"}
  defp month_label(month), do: elem(@month_abbr, month - 1)

  defp cancel_all_uploads(socket) do
    Enum.reduce(socket.assigns.uploads.statements.entries, socket, fn entry, acc ->
      cancel_upload(acc, :statements, entry.ref)
    end)
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
  defp extrato_tip("outro"), do: "Apenas PDF"
  defp extrato_tip(_), do: ""

  defp fatura_tip("nubank"), do: "Recomendado: CSV"
  defp fatura_tip("bradesco"), do: "Recomendado: CSV"
  defp fatura_tip("outro"), do: "Apenas PDF"
  defp fatura_tip(_), do: ""

  defp type_badge_class("fatura"), do: "badge-warning"
  defp type_badge_class(_), do: "badge-info"

  defp type_label("fatura"), do: "Fatura"
  defp type_label(_), do: "Extrato"
end
