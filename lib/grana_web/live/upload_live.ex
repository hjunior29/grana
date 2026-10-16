defmodule GranaWeb.UploadLive do
  use GranaWeb, :live_view

  alias Grana.AI
  alias Grana.Banking
  alias Grana.Imports
  alias Grana.Workers.PlatformImportWorker
  alias Grana.Workers.StatementUploadWorker
  alias GranaWeb.AiComponents

  @per_page 20
  # Sem limite prático de arquivos: cada um vira um job do Oban e a fila cuida do resto.
  @max_files 1_000
  @max_file_size 5_000_000

  on_mount GranaWeb.ModelChoicesHook

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Upload")
      |> assign(:tab, "upload")
      |> assign(:upload_category, nil)
      |> assign(:bank, nil)
      |> assign(:statement_type, nil)
      |> assign(:delete_target, nil)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:cal_rows, [])
      |> assign(:cal_has_data, false)
      |> assign(:cal_score, nil)
      |> assign(:show_api_key_alert, false)
      |> assign(:model_choice, "")
      |> allow_statements(~w(.csv .pdf))
      # Esta tela mostra a fila inteira e trata `:imports_changed` por conta própria,
      # para também atualizar o histórico e o calendário a cada arquivo processado.
      |> detach_hook(:imports, :handle_info)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:tab, params["tab"] || socket.assigns.tab)
      |> assign(:page, parse_int(params["page"], 1))
      |> assign(:selected_ids, MapSet.new())
      |> load_statements()

    {:noreply, socket}
  end

  defp load_statements(socket) do
    %{tab: tab, page: page} = socket.assigns
    user_id = socket.assigns.current_scope.user.id

    {statements, total} =
      Banking.list_statements_paginated(user_id, page: page, per_page: @per_page)

    socket
    |> assign(:total_pages, max(1, ceil(total / @per_page)))
    |> assign(:total, total)
    |> assign(:stmt_list, Enum.map(statements, &normalize_banking_stmt/1))
    |> maybe_load_calendar(tab, user_id)
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
      filename: stmt.filename,
      period_start: stmt.period_start,
      period_end: stmt.period_end,
      total_transactions: stmt.total_transactions,
      inserted_at: stmt.inserted_at,
      status: stmt.status,
      ai_provider: stmt.ai_provider,
      ai_model: stmt.ai_model,
      link: ~p"/transactions?statement_id=#{stmt.id}"
    }
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, :model_choice, params["model"] || socket.assigns.model_choice)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/upload?tab=#{tab}")}
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
      |> allow_statements(accept)

    {:noreply, socket}
  end

  def handle_event("select-type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :statement_type, type)}
  end

  # Upload category selection (banking vs platform)

  def handle_event("select_upload_category", %{"category" => "banking"}, socket) do
    socket =
      socket
      |> assign(:upload_category, "banking")
      |> assign(:bank, nil)
      |> assign(:statement_type, nil)
      |> cancel_all_uploads()
      |> allow_statements(~w(.csv .pdf))

    {:noreply, socket}
  end

  def handle_event("select_upload_category", %{"category" => "platform"}, socket) do
    socket =
      socket
      |> assign(:upload_category, "platform")
      |> assign(:bank, nil)
      |> assign(:statement_type, nil)
      |> cancel_all_uploads()
      |> allow_statements(~w(.csv))

    {:noreply, socket}
  end

  def handle_event("upload", params, socket) do
    case socket.assigns.upload_category do
      "platform" ->
        handle_platform_upload(socket)

      _ ->
        handle_banking_upload(
          socket,
          if(params["model"] in [nil, ""], do: nil, else: params["model"])
        )
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
        |> put_flash(
          :info,
          "#{count_label(length(ids), "extrato removido", "extratos removidos")}"
        )
        |> reload_statements()

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_banking_upload(socket, choice) do
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
        case AI.resolve(scope.user, "processing", choice) do
          {:error, :no_api_key} ->
            {:noreply, assign(socket, :show_api_key_alert, true)}

          {:ok, _config} ->
            {:noreply, enqueue_statements(socket, bank, statement_type, choice)}
        end

      true ->
        {:noreply, enqueue_statements(socket, bank, statement_type, choice)}
    end
  end

  defp enqueue_statements(socket, bank, statement_type, choice) do
    enqueue(socket, StatementUploadWorker, %{
      "bank" => bank,
      "statement_type" => statement_type,
      "model" => choice
    })
  end

  # Os arquivos saem do upload para o diretório de importações e cada um vira um job;
  # o processamento segue em segundo plano, mesmo fora desta tela.
  defp enqueue(socket, worker, args) do
    user_id = socket.assigns.current_scope.user.id

    files =
      consume_uploaded_entries(socket, :statements, fn %{path: path}, entry ->
        {:ok, %{filename: entry.client_name, path: Imports.store!(path)}}
      end)

    Imports.enqueue(user_id, worker, args, files)
    assign(socket, :import_queue, Imports.queue(user_id))
  end

  # PDFs que conseguimos extrair de forma determinística (pdftotext) não exigem
  # API key. A IA só entra como fallback (PDF escaneado / sem camada de texto).
  defp deterministic_pdf?("bradesco", "extrato"), do: true
  defp deterministic_pdf?(_bank, _statement_type), do: false

  defp handle_platform_upload(socket),
    do: {:noreply, enqueue(socket, PlatformImportWorker, %{})}

  defp reload_statements(socket) do
    {:noreply, push_patch(socket, to: ~p"/upload?tab=historico&page=#{socket.assigns.page}")}
  end

  @impl true
  def handle_info(:imports_changed, socket) do
    finished = socket.assigns.import_queue.finished
    queue = Imports.queue(socket.assigns.current_scope.user.id)
    socket = assign(socket, :import_queue, queue)

    # Cada arquivo que termina pode criar um extrato: histórico e calendário acompanham.
    socket = if queue.finished != finished, do: load_statements(socket), else: socket
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto scrollbar-gutter">
        <.page_header title="Importar" subtitle="Importe e gerencie seus extratos e faturas" />

        <.tabs>
          <:tab
            label="Importar"
            icon="hero-cloud-arrow-up"
            active={@tab == "upload"}
            event="switch_tab"
            value="upload"
          />
          <:tab
            label="Histórico"
            icon="hero-document-text"
            count={if @total > 0, do: @total}
            active={@tab == "historico"}
            event="switch_tab"
            value="historico"
          />
          <:tab
            label="Calendário"
            icon="hero-calendar-days"
            active={@tab == "calendario"}
            event="switch_tab"
            value="calendario"
          />
        </.tabs>

        <div :if={@tab == "upload"}>
          <GranaWeb.ImportComponents.import_panel
            :if={@import_queue.total > 0}
            queue={@import_queue}
          />

          <%!-- Upload Category Selection --%>
          <div class="mb-8 grid grid-cols-1 gap-4 md:grid-cols-2">
            <.option_card
              title="Fatura / Extrato"
              description="Conta corrente e cartão de crédito"
              selected={@upload_category == "banking"}
              phx-click="select_upload_category"
              phx-value-category="banking"
            >
              <:leading>
                <span class="grid size-12 shrink-0 place-items-center rounded-full bg-base-300">
                  <.icon name="hero-banknotes" class="size-6 text-info" />
                </span>
              </:leading>
            </.option_card>

            <.option_card
              title="Grana (exportação)"
              description="Reimporte um CSV exportado da plataforma"
              selected={@upload_category == "platform"}
              phx-click="select_upload_category"
              phx-value-category="platform"
            >
              <:leading>
                <span class="grid size-12 shrink-0 place-items-center rounded-full bg-base-300">
                  <.icon name="hero-arrow-up-tray" class="size-6 text-secondary" />
                </span>
              </:leading>
            </.option_card>
          </div>

          <div :if={@upload_category == "banking"}>
            <div class="mb-8 grid grid-cols-1 gap-4 md:grid-cols-3">
              <.option_card
                title="Nubank"
                description="Extrato ou fatura CSV/PDF"
                selected={@bank == "nubank"}
                phx-click="select-bank"
                phx-value-bank="nubank"
              >
                <:leading>
                  <img
                    src={~p"/images/nubank-logo.png"}
                    alt="Nubank"
                    class="size-12 shrink-0 rounded-full"
                  />
                </:leading>
              </.option_card>

              <.option_card
                title="Bradesco"
                description="Extrato ou fatura CSV/PDF"
                selected={@bank == "bradesco"}
                phx-click="select-bank"
                phx-value-bank="bradesco"
              >
                <:leading>
                  <img
                    src={~p"/images/bradesco-logo.png"}
                    alt="Bradesco"
                    class="size-12 shrink-0 rounded-full"
                  />
                </:leading>
              </.option_card>

              <.option_card
                title="Outro banco"
                description="Qualquer banco via PDF + IA"
                selected={@bank == "outro"}
                phx-click="select-bank"
                phx-value-bank="outro"
              >
                <:leading>
                  <span class="grid size-12 shrink-0 place-items-center rounded-full bg-base-300">
                    <.icon name="hero-building-library" class="size-6" />
                  </span>
                </:leading>
              </.option_card>
            </div>

            <div :if={@bank} class="mb-8 grid grid-cols-1 gap-4 md:grid-cols-2">
              <.option_card
                title="Extrato"
                description="Conta corrente: entradas e saídas"
                hint={extrato_tip(@bank)}
                selected={@statement_type == "extrato"}
                phx-click="select-type"
                phx-value-type="extrato"
              >
                <:leading><.icon name="hero-banknotes" class="size-8 shrink-0 text-info" /></:leading>
              </.option_card>

              <.option_card
                title="Fatura"
                description="Cartão de crédito: gastos e parcelas"
                hint={fatura_tip(@bank)}
                selected={@statement_type == "fatura"}
                phx-click="select-type"
                phx-value-type="fatura"
              >
                <:leading>
                  <.icon name="hero-credit-card" class="size-8 shrink-0 text-warning" />
                </:leading>
              </.option_card>
            </div>

            <div :if={@bank && @statement_type} class="card bg-base-200 mb-8 p-6 sm:p-8">
              <.statements_form
                form_id="upload-form"
                drop_id="drop-zone"
                prompt={
                  if @bank == "outro",
                    do: "Arraste arquivos PDF, ou clique para selecionar",
                    else: "Arraste arquivos CSV ou PDF, ou clique para selecionar"
                }
                submit="Processar"
                uploads={@uploads}
              >
                <:extra>
                  <AiComponents.model_picker
                    id="upload-model"
                    choices={@model_choices}
                    default={@model_defaults["processing"]}
                    value={@model_choice}
                    pdf
                  />
                </:extra>
              </.statements_form>
            </div>
          </div>

          <%!-- Platform export re-import --%>
          <div :if={@upload_category == "platform"}>
            <div class="card bg-base-200 mb-8 p-6 sm:p-8">
              <p class="ui-body ui-text-secondary mb-4">
                Envie um ou mais CSVs exportados pelo próprio Grana (de transações bancárias).
                O banco/origem e as categorias são detectados e recriados automaticamente; reimportar não duplica.
              </p>
              <.statements_form
                form_id="upload-form-platform"
                drop_id="drop-zone-platform"
                prompt="Arraste CSVs exportados do Grana, ou clique para selecionar"
                submit="Importar"
                uploads={@uploads}
              />
            </div>
          </div>
        </div>

        <div :if={@tab == "historico"}>
          <div class="mb-4 flex items-center justify-between">
            <span class="ui-body ui-text-secondary">
              {count_label(@total, "extrato", "extratos")}
            </span>
          </div>

          <.empty_state
            :if={@stmt_list == []}
            id="statements-empty"
            icon="hero-document-text"
            title="Nenhum extrato encontrado"
            text="Importe um extrato para começar."
          >
            <:action>
              <.button
                type="button"
                variant="primary"
                icon="hero-cloud-arrow-up"
                phx-click="switch_tab"
                phx-value-tab="upload"
              >
                Importar extrato
              </.button>
            </:action>
          </.empty_state>

          <div :if={@stmt_list != []}>
            <div class={[
              "mb-4 flex h-8 items-center gap-3",
              MapSet.size(@selected_ids) == 0 && "invisible"
            ]}>
              <span class="ui-body ui-text-secondary">
                {count_label(MapSet.size(@selected_ids), "selecionado", "selecionados")}
              </span>
              <.button
                id="bulk-delete"
                type="button"
                variant="danger"
                size="sm"
                icon="hero-trash"
                phx-click="confirm_bulk_delete"
              >
                Remover selecionados
              </.button>
            </div>

            <div class="overflow-x-auto">
              <table id="statements-table" class="table">
                <thead>
                  <tr>
                    <th class="w-10">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        aria-label="Selecionar todos"
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
                  <tr :for={stmt <- @stmt_list} id={"statement-#{stmt.composite_id}"} class="hover">
                    <td class="ui-st-check">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        aria-label="Selecionar extrato"
                        checked={MapSet.member?(@selected_ids, stmt.composite_id)}
                        phx-click="toggle_select"
                        phx-value-id={stmt.composite_id}
                      />
                    </td>
                    <td class="ui-st-origin">
                      <.link navigate={stmt.link} class="flex items-center gap-3">
                        <div
                          :if={stmt.logo}
                          class="size-8 shrink-0 overflow-hidden rounded-full bg-base-300"
                        >
                          <img src={stmt.logo} alt={stmt.name} />
                        </div>
                        <div
                          :if={!stmt.logo}
                          class="grid size-8 shrink-0 place-items-center rounded-full bg-base-300"
                        >
                          <.icon name="hero-building-library" class="size-4" />
                        </div>
                        <span class="ui-body truncate font-medium">{stmt.name}</span>
                      </.link>
                    </td>
                    <td
                      class="ui-st-type"
                      phx-click={
                        JS.toggle_class("ui-row-open", to: "#statement-#{stmt.composite_id}")
                      }
                    >
                      <.tag kind="neutro">{stmt.type_label}</.tag>
                      <.icon
                        name="hero-chevron-down"
                        class="ui-txn-chevron ui-text-tertiary ml-1 size-3 sm:hidden"
                      />
                    </td>
                    <td class="ui-st-detail">
                      <.link navigate={stmt.link} class="ui-private-name ui-body hover:underline">
                        {stmt.filename}
                      </.link>
                      <span
                        :if={stmt.ai_model}
                        id={"statement-model-#{stmt.raw_id}"}
                        class="ui-caption mt-0.5 flex items-center gap-1"
                        title={"Processado por IA: #{stmt.ai_provider} · #{stmt.ai_model}"}
                      >
                        <.icon name="hero-cpu-chip" class="size-3.5 shrink-0" /> {stmt.ai_model}
                      </span>
                    </td>
                    <td class="ui-st-detail ui-body ui-text-secondary">
                      {if stmt.period_start,
                        do: Calendar.strftime(stmt.period_start, "%d/%m/%Y"),
                        else: "—"} a {if stmt.period_end,
                        do: Calendar.strftime(stmt.period_end, "%d/%m/%Y"),
                        else: "—"}
                    </td>
                    <td class="ui-st-detail">
                      <.tag kind={if stmt.status == "completed", do: "ativo", else: "pendente"}>
                        {stmt.total_transactions} transações
                      </.tag>
                    </td>
                    <td class="ui-st-detail ui-body ui-text-secondary">
                      {format_datetime_br(stmt.inserted_at)}
                    </td>
                    <td class="ui-st-actions">
                      <.button
                        type="button"
                        variant="ghost"
                        size="sm"
                        icon="hero-trash"
                        class="btn-square text-error"
                        aria-label="Remover extrato"
                        phx-click="confirm_delete"
                        phx-value-id={stmt.composite_id}
                      >
                        <span class="sr-only">Remover extrato</span>
                      </.button>
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
                <span :if={p == :dots} class="ui-text-tertiary px-2">…</span>
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

          <.confirm_modal
            :if={@delete_target}
            id="delete_modal"
            open
            title="Remover extrato"
            confirm="Remover"
            loading="Removendo…"
            on_confirm={JS.push("delete")}
            on_cancel={JS.push("cancel_delete")}
          >
            <p :if={match?({:single, _}, @delete_target)}>
              Tem certeza que deseja remover o extrato <span class="ui-private-name font-semibold">{elem(@delete_target, 1).filename}</span>?
              Todas as {elem(@delete_target, 1).total_transactions} transações associadas serão removidas permanentemente.
            </p>
            <p :if={match?({:bulk, _}, @delete_target)}>
              Tem certeza que deseja remover
              <span class="font-semibold">
                {count_label(elem(@delete_target, 1), "extrato", "extratos")}
              </span>
              e todas as transações associadas? Esta ação é permanente.
            </p>
          </.confirm_modal>
        </div>

        <div :if={@tab == "calendario"}>
          <div class="mb-6">
            <h2 class="ui-card-title">Calendário de importações</h2>
            <p class="ui-help mt-1 sm:text-sm">
              Cada quadrado é um mês. Quanto mais intenso, mais tipos de documento (extrato ou
              fatura) você importou naquele mês. Passe o mouse para ver os detalhes.
            </p>
          </div>

          <.empty_state
            :if={!@cal_has_data}
            id="calendar-empty"
            icon="hero-calendar-days"
            title="Ainda não há dados importados"
            text="Importe extratos ou faturas na aba Importar."
          >
            <:action>
              <.button
                type="button"
                variant="secondary"
                size="sm"
                phx-click="switch_tab"
                phx-value-tab="upload"
              >
                Ir para Importar
              </.button>
            </:action>
          </.empty_state>

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
                        class="grana-calendar-month-label ui-caption flex-1 min-w-0 text-center font-medium sm:text-sm"
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
                    <span class="ui-text-secondary ml-3">
                      Tom cheio = extrato + fatura no mês.
                    </span>
                  </div>
                </div>

                <%!-- Pontuação de cobertura (donut), no mesmo card --%>
                <div class="grana-calendar-score flex flex-col items-center text-center gap-1 shrink-0 lg:w-64 lg:border-l lg:border-base-content/10 lg:pl-8">
                  <h3 class="ui-section-title">Cobertura de importações</h3>
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
                  <p class="ui-help">
                    {@cal_score.imports} de {@cal_score.ideal} importações
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <.ai_required_modal
          :if={@show_api_key_alert}
          reason="Ler PDFs usa IA para extrair as transações do arquivo."
        />
      </div>
    </Layouts.app>
    """
  end

  attr :form_id, :string, required: true
  attr :drop_id, :string, required: true
  attr :prompt, :string, required: true
  attr :submit, :string, required: true
  attr :uploads, :any, required: true
  slot :extra, doc: "next to the submit button (e.g. the AI model picker)"

  defp statements_form(assigns) do
    ~H"""
    <form id={@form_id} phx-submit="upload" phx-change="validate">
      <div class="flex flex-col items-center gap-4">
        <div
          id={@drop_id}
          class="ui-dropzone w-full"
          phx-drop-target={@uploads.statements.ref}
          phx-hook="DropZone"
        >
          <.live_file_input upload={@uploads.statements} class="hidden" />
          <label for={@uploads.statements.ref} class="block cursor-pointer p-8 text-center">
            <.icon name="hero-cloud-arrow-up" class="ui-text-tertiary mx-auto mb-4 size-12" />
            <p class="ui-body font-medium">{@prompt}</p>
            <p class="ui-help mt-1">Quantos arquivos quiser, até 5MB cada</p>
          </label>
        </div>

        <ul
          :if={@uploads.statements.entries != []}
          id={"#{@form_id}-entries"}
          class="w-full divide-y divide-base-content/10"
        >
          <.item_row
            :for={entry <- @uploads.statements.entries}
            :key={entry.ref}
            title={entry.client_name}
            title_class="ui-private-name"
            subtitle={entry_subtitle(entry)}
          >
            <p
              :for={err <- upload_errors(@uploads.statements, entry)}
              class="ui-help text-error"
            >
              {upload_error_to_string(err)}
            </p>
            <:leading><.icon name="hero-document-text" class="size-5 shrink-0" /></:leading>
            <:actions>
              <.button
                type="button"
                variant="ghost"
                size="sm"
                icon="hero-x-mark"
                class="btn-square"
                aria-label="Remover arquivo"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
              >
                <span class="sr-only">Remover arquivo</span>
              </.button>
            </:actions>
          </.item_row>
        </ul>

        <p :for={err <- upload_errors(@uploads.statements)} class="ui-body text-error">
          {upload_error_to_string(err)}
        </p>

        <div class="flex w-full flex-col items-center gap-2 sm:w-auto sm:flex-row">
          <.button
            variant="primary"
            class="w-full sm:w-auto"
            phx-disable-with="Enviando…"
            disabled={
              @uploads.statements.entries == [] or
                Enum.any?(@uploads.statements.entries, &(!&1.valid?))
            }
          >
            {submit_label(@submit, length(@uploads.statements.entries))}
          </.button>
          {render_slot(@extra)}
        </div>
        <p :if={@uploads.statements.entries == []} class="ui-help">
          Escolha um arquivo para continuar.
        </p>
      </div>
    </form>
    """
  end

  defp submit_label(label, count) when count > 1, do: "#{label} #{count} arquivos"
  defp submit_label(label, _count), do: label

  # Enquanto o navegador envia (depois de clicar em Processar), mostra quanto já subiu.
  defp entry_subtitle(%{progress: progress} = entry) when progress in 1..99,
    do: "#{format_bytes(entry.client_size)} · enviando #{progress}%"

  defp entry_subtitle(entry), do: format_bytes(entry.client_size)

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

  defp cell_class(%{future?: true}), do: "calendar-count-future"
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

  defp allow_statements(socket, accept) do
    allow_upload(socket, :statements,
      accept: accept,
      max_entries: @max_files,
      max_file_size: @max_file_size
    )
  end

  defp cancel_all_uploads(socket) do
    Enum.reduce(socket.assigns.uploads.statements.entries, socket, fn entry, acc ->
      cancel_upload(acc, :statements, entry.ref)
    end)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  defp upload_error_to_string(:too_large), do: "Arquivo muito grande (máximo 5MB)"
  defp upload_error_to_string(:not_accepted), do: "Tipo de arquivo não aceito (use CSV ou PDF)"

  defp upload_error_to_string(:too_many_files),
    do: "Muitos arquivos de uma vez (máximo #{@max_files})"

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

  defp type_label("fatura"), do: "Fatura"
  defp type_label(_), do: "Extrato"
end
