defmodule GranaWeb.UploadLive do
  use GranaWeb, :live_view

  alias Grana.Banking

  alias Grana.Investments

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
      |> assign(:investment_provider, nil)
      |> assign(:processing, false)
      |> assign(:results, [])
      |> assign(:progress_current, 0)
      |> assign(:progress_total, 0)
      |> assign(:progress_filename, "")
      |> assign(:progress_ai, false)
      |> assign(:delete_target, nil)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:history_filter, "all")
      |> assign(:show_api_key_alert, false)
      |> assign(:roadmap_url, Application.get_env(:grana, :roadmap_url))
      |> assign(:roadmap_dismissed, false)
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
    history_filter = params["source"] || "all"
    user_id = socket.assigns.current_scope.user.id

    # Fetch all statements from both sources
    banking_stmts =
      if history_filter in ["all", "banking"] do
        Banking.list_statements(user_id)
        |> Enum.map(&normalize_banking_stmt/1)
      else
        []
      end

    inv_stmts =
      if history_filter in ["all", "investment"] do
        Investments.list_statements(user_id)
        |> Enum.map(&normalize_inv_stmt/1)
      else
        []
      end

    # Merge, sort by inserted_at desc, and paginate
    all_stmts =
      (banking_stmts ++ inv_stmts)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    total = length(all_stmts)
    total_pages = max(1, ceil(total / @per_page))
    offset = (page - 1) * @per_page

    page_stmts = Enum.slice(all_stmts, offset, @per_page)

    socket =
      socket
      |> assign(:tab, tab)
      |> assign(:page, page)
      |> assign(:total_pages, total_pages)
      |> assign(:total, total)
      |> assign(:stmt_list, page_stmts)
      |> assign(:history_filter, history_filter)
      |> assign(:selected_ids, MapSet.new())

    {:noreply, socket}
  end

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
      link: "/transactions?tab=banking&statement_id=#{stmt.id}"
    }
  end

  defp normalize_inv_stmt(stmt) do
    inst_name = if stmt.institution, do: stmt.institution.name, else: "—"
    inst_logo = if stmt.institution, do: Grana.Investments.Institution.logo_url(stmt.institution)

    %{
      composite_id: "inv_#{stmt.id}",
      raw_id: stmt.id,
      source: "investment",
      name: inst_name,
      logo: inst_logo,
      type_label: "Investimento",
      type_badge: "badge-success",
      filename: stmt.filename,
      period_start: stmt.period_start,
      period_end: stmt.period_end,
      total_transactions: stmt.total_transactions || 0,
      inserted_at: stmt.inserted_at,
      status: stmt.status,
      link: "/transactions?tab=investments&statement_id=#{stmt.id}"
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

  def handle_event("dismiss_roadmap", _params, socket) do
    {:noreply, assign(socket, :roadmap_dismissed, true)}
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

  # Upload category selection (banking vs investment)

  def handle_event("select_upload_category", _params, %{assigns: %{processing: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("select_upload_category", %{"category" => "banking"}, socket) do
    socket =
      socket
      |> assign(:upload_category, "banking")
      |> assign(:bank, nil)
      |> assign(:statement_type, nil)
      |> assign(:investment_provider, nil)
      |> cancel_all_uploads()
      |> allow_upload(:statements,
        accept: ~w(.csv .pdf),
        max_entries: 12,
        max_file_size: 5_000_000
      )

    {:noreply, socket}
  end

  def handle_event("select_upload_category", %{"category" => "investment"}, socket) do
    socket =
      socket
      |> assign(:upload_category, "investment")
      |> assign(:bank, nil)
      |> assign(:statement_type, nil)
      |> assign(:investment_provider, nil)
      |> cancel_all_uploads()
      |> allow_upload(:statements,
        accept: ~w(.xlsx .xls .pdf .csv),
        max_entries: 12,
        max_file_size: 5_000_000
      )

    {:noreply, socket}
  end

  def handle_event(
        "select_investment_provider",
        _params,
        %{assigns: %{processing: true}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("select_investment_provider", %{"provider" => "b3"}, socket) do
    socket =
      socket
      |> assign(:investment_provider, "b3")
      |> cancel_all_uploads()
      |> allow_upload(:statements,
        accept: ~w(.xlsx .xls .pdf),
        max_entries: 12,
        max_file_size: 5_000_000
      )

    {:noreply, socket}
  end

  def handle_event("select_investment_provider", %{"provider" => "gcb"}, socket) do
    socket =
      socket
      |> assign(:investment_provider, "gcb")
      |> cancel_all_uploads()
      |> allow_upload(:statements,
        accept: ~w(.csv .pdf),
        max_entries: 12,
        max_file_size: 5_000_000
      )

    {:noreply, socket}
  end

  def handle_event("upload", _params, socket) do
    case socket.assigns.upload_category do
      "investment" -> handle_investment_upload(socket)
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
    case socket.assigns.delete_target do
      {:single, stmt} ->
        delete_by_composite(stmt)

        socket
        |> assign(:delete_target, nil)
        |> put_flash(:info, "Extrato removido com sucesso")
        |> reload_statements()

      {:bulk, _count} ->
        selected = MapSet.to_list(socket.assigns.selected_ids)

        {bank_ids, inv_ids} = split_composite_ids(selected)

        if bank_ids != [], do: Banking.delete_statements(bank_ids)
        if inv_ids != [], do: Investments.delete_statements(inv_ids)

        total = length(bank_ids) + length(inv_ids)

        socket
        |> assign(:delete_target, nil)
        |> assign(:selected_ids, MapSet.new())
        |> put_flash(:info, "#{total} extrato(s) removido(s)")
        |> reload_statements()

      _ ->
        {:noreply, socket}
    end
  end

  defp delete_by_composite(%{source: "banking", raw_id: id}) do
    stmt = Grana.Repo.get!(Grana.Banking.BankStatement, id)
    Banking.delete_statement(stmt)
  end

  defp delete_by_composite(%{source: "investment", raw_id: id}) do
    stmt = Grana.Repo.get!(Grana.Investments.Statement, id)
    Investments.delete_statement(stmt)
  end

  defp split_composite_ids(ids) do
    Enum.reduce(ids, {[], []}, fn id, {banks, invs} ->
      case id do
        "bank_" <> raw -> {[String.to_integer(raw) | banks], invs}
        "inv_" <> raw -> {banks, [String.to_integer(raw) | invs]}
        _ -> {banks, invs}
      end
    end)
  end

  defp handle_banking_upload(socket) do
    %{current_scope: scope} = socket.assigns
    bank = socket.assigns.bank
    statement_type = socket.assigns.statement_type

    has_pdf =
      Enum.any?(socket.assigns.uploads.statements.entries, fn entry ->
        String.ends_with?(String.downcase(entry.client_name), ".pdf")
      end)

    needs_api_key = has_pdf or bank == "outro"

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

  defp handle_investment_upload(socket) do
    %{current_scope: scope} = socket.assigns

    institution_slug = socket.assigns.investment_provider

    has_pdf =
      Enum.any?(socket.assigns.uploads.statements.entries, fn entry ->
        String.ends_with?(String.downcase(entry.client_name), ".pdf")
      end)

    if has_pdf do
      case Grana.Accounts.get_user_ai_config(scope.user.id) do
        {:error, :no_api_key} ->
          {:noreply, assign(socket, :show_api_key_alert, true)}

        {:ok, _config} ->
          socket = assign(socket, :processing, true)
          send(self(), {:process_investment_uploads, institution_slug, scope.user.id})
          {:noreply, socket}
      end
    else
      socket = assign(socket, :processing, true)
      send(self(), {:process_investment_uploads, institution_slug, scope.user.id})
      {:noreply, socket}
    end
  end

  defp reload_statements(socket) do
    source = Map.get(socket.assigns, :history_filter, "all")

    {:noreply,
     push_patch(socket, to: "/upload?tab=historico&page=#{socket.assigns.page}&source=#{source}")}
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

  def handle_info({:process_investment_uploads, institution_slug, user_id}, socket) do
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
      institution_slug: institution_slug,
      user_id: user_id,
      topic: topic
    }
    |> Grana.Workers.InvestmentUploadWorker.new()
    |> Oban.insert()

    {:noreply,
     assign(socket,
       upload_bank: institution_slug,
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

    socket =
      if all_warnings != [] do
        warning_count = length(all_warnings)
        summary = Enum.take(all_warnings, 5) |> Enum.join(" | ")
        extra = if warning_count > 5, do: " (+#{warning_count - 5} mais)", else: ""
        put_flash(socket, :warning, "#{warning_count} linha(s) ignorada(s): #{summary}#{extra}")
      else
        socket
      end

    source = Map.get(socket.assigns, :history_filter, "all")

    {:noreply,
     push_patch(socket, to: "/upload?tab=#{socket.assigns.tab}&page=1&source=#{source}")}
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

  defp format_error(reason, _bank), do: reason

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto scrollbar-gutter">
        <div class="mb-4 sm:mb-8 text-center sm:text-left">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Upload</h1>
          <p class="text-xs sm:text-sm opacity-60 mt-1">Importe e gerencie seus extratos e faturas</p>
        </div>

        <div role="tablist" class="tabs tabs-border mb-8 -ml-2">
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
              phx-value-category="investment"
              disabled={@processing}
              class={[
                "card bg-base-200 p-6 cursor-pointer transition-all hover:shadow-lg border-2",
                (@upload_category == "investment" && "border-primary") || "border-transparent"
              ]}
            >
              <div class="flex items-center gap-4">
                <div class="w-12 h-12 rounded-full bg-base-300 flex items-center justify-center">
                  <.icon name="hero-chart-bar" class="size-6 text-success" />
                </div>
                <div class="text-left">
                  <h3 class="font-semibold text-lg">Investimento</h3>
                  <p class="text-sm opacity-70">Ações, FIIs, renda fixa e mais</p>
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

          <%!-- Investment Upload Flow --%>
          <div :if={@upload_category == "investment"}>
            <%!-- Provider Selection --%>
            <div class={[
              "grid grid-cols-1 md:grid-cols-2 gap-6 mb-8",
              @processing && "opacity-50 pointer-events-none"
            ]}>
              <button
                phx-click="select_investment_provider"
                phx-value-provider="b3"
                disabled={@processing}
                class={[
                  "card bg-base-200 p-6 cursor-pointer transition-all hover:shadow-lg border-2",
                  (@investment_provider == "b3" && "border-primary") || "border-transparent"
                ]}
              >
                <div class="flex items-center gap-4">
                  <img
                    src={~p"/images/b3-logo.png"}
                    alt="B3"
                    class="w-12 h-12 rounded-full"
                  />
                  <div class="text-left">
                    <h3 class="font-semibold text-lg">B3</h3>
                    <p class="text-sm opacity-70">Negociações da bolsa brasileira</p>
                    <p class="text-xs opacity-50 mt-1">Recomendado: XLSX</p>
                  </div>
                </div>
              </button>

              <button
                phx-click="select_investment_provider"
                phx-value-provider="gcb"
                disabled={@processing}
                class={[
                  "card bg-base-200 p-6 cursor-pointer transition-all hover:shadow-lg border-2",
                  (@investment_provider == "gcb" && "border-primary") || "border-transparent"
                ]}
              >
                <div class="flex items-center gap-4">
                  <div class="w-12 h-12 rounded-full overflow-hidden bg-base-300 shrink-0">
                    <img src={~p"/images/gcb-logo.png"} alt="GCB" />
                  </div>
                  <div class="text-left">
                    <h3 class="font-semibold text-lg">GCB</h3>
                    <p class="text-sm opacity-70">Notas fiscais, debêntures, precatórios</p>
                    <p class="text-xs opacity-50 mt-1">Recomendado: CSV</p>
                  </div>
                </div>
              </button>
            </div>

            <%!-- Investment Upload Form --%>
            <div
              :if={@investment_provider in ["b3", "gcb"]}
              class="card bg-base-200 p-8 mb-8"
            >
              <div class="text-center mb-4">
                <p class="text-sm opacity-60">
                  <%= if @investment_provider == "b3" do %>
                    Faça upload do extrato de negociação da B3 (XLSX recomendado, ou PDF)
                  <% else %>
                    Faça upload do extrato da GCB (CSV recomendado, ou PDF)
                  <% end %>
                </p>
              </div>
              <form id="upload-form-inv" phx-submit="upload" phx-change="validate">
                <div class="flex flex-col items-center gap-4">
                  <div
                    id="drop-zone-inv"
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
                        <%= if @investment_provider == "b3" do %>
                          Arraste arquivos XLSX ou PDF, ou clique para selecionar
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
                    id="upload-progress-inv"
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

          <div :if={@roadmap_url && !@roadmap_dismissed} class="alert alert-info alert-soft mt-8">
            <.icon name="hero-light-bulb-mini" class="size-5" />
            <div>
              <span class="font-medium">Seu banco ou corretora não está na lista?</span>
              <br />
              <.link href={@roadmap_url} target="_blank" class="link">
                Sugira no nosso roadmap
              </.link>
              e adicionaremos suporte.
            </div>
            <button phx-click="dismiss_roadmap" class="btn btn-sm btn-ghost btn-circle">
              <.icon name="hero-x-mark-mini" class="size-4" />
            </button>
          </div>
        </div>

        <div :if={@tab == "historico"}>
          <div class="flex items-center gap-2 mb-4">
            <.link
              patch={~p"/upload?tab=historico&source=all"}
              class={["btn btn-sm", (@history_filter == "all" && "btn-primary") || "btn-ghost"]}
            >
              Todos
            </.link>
            <.link
              patch={~p"/upload?tab=historico&source=banking"}
              class={["btn btn-sm", (@history_filter == "banking" && "btn-primary") || "btn-ghost"]}
            >
              <.icon name="hero-banknotes" class="size-3.5" /> Bancária
            </.link>
            <.link
              patch={~p"/upload?tab=historico&source=investment"}
              class={["btn btn-sm", (@history_filter == "investment" && "btn-primary") || "btn-ghost"]}
            >
              <.icon name="hero-chart-bar" class="size-3.5" /> Investimentos
            </.link>
            <span class="text-sm opacity-50 ml-2">{@total} extrato(s)</span>
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
                patch={"/upload?tab=historico&source=#{@history_filter}&page=#{@page - 1}"}
                class="btn btn-sm btn-ghost"
              >
                <.icon name="hero-chevron-left" class="size-4" />
              </.link>
              <span :for={p <- page_range(@page, @total_pages)}>
                <.link
                  :if={is_integer(p)}
                  patch={"/upload?tab=historico&source=#{@history_filter}&page=#{p}"}
                  class={["btn btn-sm", (p == @page && "btn-primary") || "btn-ghost"]}
                >
                  {p}
                </.link>
                <span :if={p == :dots} class="px-2 opacity-40">...</span>
              </span>
              <.link
                :if={@page < @total_pages}
                patch={"/upload?tab=historico&source=#{@history_filter}&page=#{@page + 1}"}
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
