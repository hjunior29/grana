defmodule GranaWeb.AnalysisLive do
  use GranaWeb, :live_view

  alias Grana.Banking

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    Banking.ensure_default_categories(user_id)

    # Banking filter data
    banks = Banking.available_banks(user_id)
    years = Banking.available_years(user_id)
    months = Banking.available_months(user_id)

    current_year =
      case years do
        [_ | _] -> List.last(years)
        [] -> Date.utc_today().year
      end

    current_month =
      months
      |> Enum.filter(fn {y, _m} -> y == current_year end)
      |> Enum.map(fn {_y, m} -> m end)
      |> Enum.max(fn -> 0 end)

    analyses = Banking.list_ai_analyses(user_id)

    socket =
      socket
      |> assign(:page_title, "Análise")
      |> assign(:banks, banks)
      |> assign(:available_years, years)
      |> assign(:available_months, months)
      |> assign(:analyses, analyses)
      |> assign(:loading, false)
      |> assign(:show_api_key_alert, false)
      |> assign(:collapsed_years, MapSet.new())
      |> assign(:filters, %{
        year: current_year,
        month: current_month,
        bank: "all",
        type: "all",
        statement_type: "all"
      })
      |> assign(:custom_prompt, "")
      |> assign(:prompt_form, to_form(%{"prompt" => ""}))
      |> assign(:expanded_analyses, expanded_default(analyses))
      |> assign(:delete_target, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ── Banking Events ──

  @impl true
  def handle_event("select_year", %{"year" => year_str}, socket) do
    year = safe_to_int(year_str, Date.utc_today().year)
    {:noreply, socket |> put_filter(:year, year) |> put_filter(:month, 0)}
  end

  def handle_event("select_month", %{"month" => "all"}, socket) do
    {:noreply, put_filter(socket, :month, 0)}
  end

  def handle_event("select_month", %{"month" => month_str}, socket) do
    month = safe_to_int(month_str, 0)
    {:noreply, put_filter(socket, :month, month)}
  end

  def handle_event("select_bank", %{"bank" => bank}, socket) do
    {:noreply, put_filter(socket, :bank, bank)}
  end

  def handle_event("select_source", %{"source" => source}, socket) do
    {:noreply, put_filter(socket, :statement_type, source)}
  end

  def handle_event("select_txn_type", %{"txn_type" => txn_type}, socket) do
    {:noreply, put_filter(socket, :type, txn_type)}
  end

  def handle_event("update_prompt", %{"prompt" => prompt}, socket) do
    {:noreply,
     socket
     |> assign(:custom_prompt, prompt)
     |> assign(:prompt_form, to_form(%{"prompt" => prompt}))}
  end

  def handle_event("analyze", _params, socket) do
    %{current_scope: scope, custom_prompt: prompt, filters: filters} = socket.assigns
    context = "banking"
    custom_prompt = if prompt == "", do: nil, else: prompt

    # Check for duplicate analysis in the last 2 minutes
    if has_recent_duplicate?(socket.assigns.analyses, context, filters, custom_prompt) do
      {:noreply,
       put_flash(
         socket,
         :warning,
         "Já existe uma análise recente com os mesmos filtros. Aguarde 2 minutos ou altere os filtros."
       )}
    else
      case Grana.Accounts.get_user_ai_config(scope.user.id) do
        {:error, :no_api_key} ->
          {:noreply, assign(socket, :show_api_key_alert, true)}

        {:ok, _config} ->
          topic = "analysis:#{scope.user.id}:#{System.unique_integer([:positive])}"
          Phoenix.PubSub.subscribe(Grana.PubSub, topic)

          %{
            user_id: scope.user.id,
            context: context,
            filters: stringify_keys(filters),
            custom_prompt: custom_prompt,
            topic: topic
          }
          |> Grana.Workers.AIAnalysisWorker.new()
          |> Oban.insert()

          {:noreply, assign(socket, :loading, true)}
      end
    end
  end

  def handle_event("set_chip", %{"text" => text}, socket) do
    {:noreply,
     socket
     |> assign(:custom_prompt, text)
     |> assign(:prompt_form, to_form(%{"prompt" => text}))}
  end

  def handle_event("toggle_analysis", %{"id" => id_str}, socket) do
    case safe_to_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        expanded = socket.assigns.expanded_analyses

        expanded =
          if MapSet.member?(expanded, id),
            do: MapSet.delete(expanded, id),
            else: MapSet.put(expanded, id)

        {:noreply, assign(socket, :expanded_analyses, expanded)}
    end
  end

  def handle_event("dismiss_api_alert", _params, socket) do
    {:noreply, assign(socket, :show_api_key_alert, false)}
  end

  def handle_event("toggle_year", %{"year" => year}, socket) do
    case safe_to_int(year) do
      nil ->
        {:noreply, socket}

      year ->
        collapsed = socket.assigns.collapsed_years

        collapsed =
          if MapSet.member?(collapsed, year),
            do: MapSet.delete(collapsed, year),
            else: MapSet.put(collapsed, year)

        {:noreply, assign(socket, :collapsed_years, collapsed)}
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_target, safe_to_int(id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_target, nil)}
  end

  def handle_event("delete_analysis", _params, socket) do
    case socket.assigns.delete_target do
      nil ->
        {:noreply, socket}

      id ->
        user_id = socket.assigns.current_scope.user.id

        socket =
          try do
            analysis = Banking.get_ai_analysis!(id, user_id)
            {:ok, _} = Banking.delete_ai_analysis(analysis)

            socket
            |> assign(:analyses, Banking.list_ai_analyses(user_id))
            |> put_flash(:info, "Análise removida")
          rescue
            Ecto.NoResultsError ->
              put_flash(socket, :error, "Análise não encontrada.")
          end

        {:noreply, assign(socket, :delete_target, nil)}
    end
  end

  @impl true
  def handle_info({:analysis_complete, :ok}, socket) do
    analyses = Banking.list_ai_analyses(socket.assigns.current_scope.user.id)

    # Auto-expand the most recent analysis
    expanded =
      case analyses do
        [newest | _] -> MapSet.put(socket.assigns.expanded_analyses, newest.id)
        _ -> socket.assigns.expanded_analyses
      end

    socket =
      socket
      |> assign(:analyses, analyses)
      |> assign(:expanded_analyses, expanded)
      |> assign(:loading, false)
      |> put_flash(:info, "Análise concluída!")

    {:noreply, socket}
  end

  def handle_info({:analysis_complete, {:error, msg}}, socket) do
    socket =
      socket
      |> assign(:loading, false)
      |> put_flash(:error, "Erro na análise: #{msg}")

    {:noreply, socket}
  end

  # ── Helpers ──

  defp put_filter(socket, key, value) do
    filters = Map.put(socket.assigns.filters, key, value)
    assign(socket, :filters, filters)
  end

  defp safe_to_int(value, default \\ nil) do
    case value |> to_string() |> Integer.parse() do
      {n, _} -> n
      :error -> default
    end
  end

  defp expanded_default(analyses) do
    case analyses do
      [newest | _] -> MapSet.new([newest.id])
      _ -> MapSet.new()
    end
  end

  defp has_recent_duplicate?(analyses, context, filters, custom_prompt) do
    two_minutes_ago = DateTime.utc_now() |> DateTime.add(-120, :second)
    str_filters = stringify_keys(filters)

    Enum.any?(analyses, fn a ->
      recent? = DateTime.compare(a.inserted_at, two_minutes_ago) == :gt
      same_context? = a.filters_json["context"] == context
      same_year? = to_string(a.filters_json["year"]) == to_string(str_filters["year"])
      same_month? = to_string(a.filters_json["month"]) == to_string(str_filters["month"])
      same_prompt? = (a.prompt || nil) == (custom_prompt || nil)

      recent? and same_context? and same_year? and same_month? and same_prompt?
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp months_for_year(available_months, year) do
    available_months
    |> Enum.filter(fn {y, _m} -> y == year end)
    |> Enum.map(fn {_y, m} -> m end)
    |> Enum.sort()
  end

  defp bank_logo("nubank"), do: ~p"/images/nubank-logo.png"
  defp bank_logo("bradesco"), do: ~p"/images/bradesco-logo.png"
  defp bank_logo(_), do: ~p"/images/logo-32.png"

  defp source_label("extrato"), do: "Extrato"
  defp source_label("fatura"), do: "Fatura"
  defp source_label(_), do: nil

  defp type_label("debit"), do: "Despesas"
  defp type_label("credit"), do: "Receitas"
  defp type_label(_), do: nil

  defp group_by_year(analyses) do
    analyses
    |> Enum.group_by(fn a ->
      a.filters_json["year"] || a.inserted_at.year
    end)
    |> Enum.sort_by(fn {year, _} -> year end, :desc)
  end

  defp is_new_format?(analysis) do
    Map.has_key?(analysis.result_json, "nota") and Map.has_key?(analysis.result_json, "pontos")
  end

  defp score_color(nota) when is_number(nota) do
    cond do
      nota >= 8 -> "text-success bg-success/15 border-success/30"
      nota >= 6 -> "text-info bg-info/15 border-info/30"
      nota >= 4 -> "text-warning bg-warning/15 border-warning/30"
      true -> "text-error bg-error/15 border-error/30"
    end
  end

  defp score_color(_), do: "text-info bg-info/15 border-info/30"

  defp ponto_icon("positivo"), do: {"hero-check-circle", "text-success"}
  defp ponto_icon("negativo"), do: {"hero-x-circle", "text-error"}
  defp ponto_icon("dica"), do: {"hero-light-bulb", "text-warning"}
  defp ponto_icon(_), do: {"hero-minus-circle", "opacity-50"}

  defp format_datetime_br(dt) do
    dt
    |> DateTime.add(-3, :hour)
    |> Calendar.strftime("%d/%m/%Y às %H:%M")
  end

  defp format_score(nota) when is_float(nota) do
    nota |> Float.round(1) |> to_string()
  end

  defp format_score(nota) when is_integer(nota), do: "#{nota}.0"
  defp format_score(_), do: "—"

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-4 sm:mb-8 text-center sm:text-left">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Análise</h1>
          <p class="text-xs sm:text-sm opacity-60 mt-1">
            Insights inteligentes sobre suas finanças
          </p>
        </div>

        <%!-- Filters --%>
        <div :if={@available_years != []} class="mb-4 sm:mb-6 space-y-2">
          <%!-- Row 1: Year + Month --%>
          <div class="flex flex-wrap items-center gap-1 sm:gap-2">
            <div class="flex gap-1">
              <button
                :for={y <- @available_years}
                phx-click="select_year"
                phx-value-year={y}
                class={[
                  "btn btn-xs sm:btn-sm",
                  (y == @filters.year && "btn-primary") || "btn-ghost"
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
                class={["btn btn-xs", (@filters.month == 0 && "btn-primary") || "btn-ghost"]}
              >
                Ano
              </button>
              <button
                :for={m <- months_for_year(@available_months, @filters.year)}
                phx-click="select_month"
                phx-value-month={m}
                class={[
                  "btn btn-xs",
                  (@filters.month == m && "btn-primary") || "btn-ghost"
                ]}
              >
                {Banking.month_name_short(m)}
              </button>
            </div>
          </div>

          <%!-- Row 2: Bank + Source + Txn Type --%>
          <div class="flex flex-wrap items-center gap-2 sm:gap-3">
            <div :if={@banks != []} class="flex items-center gap-1">
              <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Banco</span>
              <button
                phx-click="select_bank"
                phx-value-bank="all"
                class={["btn btn-xs", (@filters.bank == "all" && "btn-primary") || "btn-ghost"]}
              >
                Todos
              </button>
              <button
                :for={b <- @banks}
                phx-click="select_bank"
                phx-value-bank={b}
                class={["btn btn-xs gap-1", (@filters.bank == b && "btn-primary") || "btn-ghost"]}
              >
                <img src={bank_logo(b)} alt="" class="w-4 h-4 rounded-full" />
                <span class="hidden sm:inline">{String.capitalize(b)}</span>
              </button>
            </div>
            <div class="flex items-center gap-1">
              <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Fonte</span>
              <button
                phx-click="select_source"
                phx-value-source="all"
                class={[
                  "btn btn-xs",
                  (@filters.statement_type == "all" && "btn-primary") || "btn-ghost"
                ]}
              >
                Todas
              </button>
              <button
                phx-click="select_source"
                phx-value-source="extrato"
                class={[
                  "btn btn-xs gap-1",
                  (@filters.statement_type == "extrato" && "btn-primary") || "btn-ghost"
                ]}
              >
                <.icon name="hero-banknotes" class="size-3" />
                <span class="hidden sm:inline">Extrato</span>
              </button>
              <button
                phx-click="select_source"
                phx-value-source="fatura"
                class={[
                  "btn btn-xs gap-1",
                  (@filters.statement_type == "fatura" && "btn-primary") || "btn-ghost"
                ]}
              >
                <.icon name="hero-credit-card" class="size-3" />
                <span class="hidden sm:inline">Fatura</span>
              </button>
            </div>
            <div class="flex items-center gap-1">
              <span class="text-xs opacity-40 mr-0.5 sm:mr-1">Tipo</span>
              <button
                phx-click="select_txn_type"
                phx-value-txn_type="all"
                class={["btn btn-xs", (@filters.type == "all" && "btn-primary") || "btn-ghost"]}
              >
                Todas
              </button>
              <button
                phx-click="select_txn_type"
                phx-value-txn_type="debit"
                class={["btn btn-xs", (@filters.type == "debit" && "btn-primary") || "btn-ghost"]}
              >
                Despesas
              </button>
              <button
                phx-click="select_txn_type"
                phx-value-txn_type="credit"
                class={["btn btn-xs", (@filters.type == "credit" && "btn-primary") || "btn-ghost"]}
              >
                Receitas
              </button>
            </div>
          </div>
        </div>

        <%!-- Prompt + Analyze --%>
        <div class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-8">
          <.form for={@prompt_form} phx-submit="analyze" phx-change="update_prompt" novalidate>
            <div class="mb-3 sm:mb-4">
              <.input
                type="textarea"
                field={@prompt_form[:prompt]}
                label="Pergunte algo sobre suas finanças (opcional)"
                placeholder="Ex: Onde posso economizar? Qual categoria cresceu mais?"
                rows={2}
              />
            </div>

            <div class="flex flex-wrap gap-1.5 mb-3">
              <button
                :for={
                  chip <- [
                    "Onde posso economizar?",
                    "Qual categoria cresceu mais?",
                    "Como estão meus gastos fixos?",
                    "Resumo do mês"
                  ]
                }
                type="button"
                phx-click="set_chip"
                phx-value-text={chip}
                class="btn btn-xs btn-outline btn-primary rounded-full font-normal"
              >
                {chip}
              </button>
            </div>

            <button
              type="submit"
              class="btn btn-primary btn-sm sm:btn-md gap-2 w-full sm:w-auto"
              disabled={@loading}
            >
              <.icon :if={!@loading} name="hero-sparkles" class="size-4" />
              {if @loading, do: "Analisando...", else: "Analisar com IA"}
            </button>
          </.form>
        </div>

        <%!-- Loading --%>
        <div :if={@loading} class="card bg-base-200 p-4 sm:p-6 mb-4 sm:mb-6">
          <div class="flex items-center gap-3">
            <span class="loading loading-spinner loading-sm text-primary" />
            <span class="text-sm opacity-60">Analisando seus dados com IA...</span>
          </div>
        </div>

        <%!-- Empty State --%>
        <div :if={@analyses == [] and !@loading} class="text-center py-10 sm:py-16">
          <.icon name="hero-sparkles" class="size-12 sm:size-16 mx-auto mb-4 opacity-20" />
          <h2 class="text-lg sm:text-xl font-semibold mb-2">Nenhuma análise ainda</h2>
          <p class="opacity-60 text-sm">Configure os filtros e clique em "Analisar com IA"</p>
        </div>

        <%!-- Analyses grouped by year --%>
        <div :if={@analyses != []} class="space-y-4 sm:space-y-6">
          <div :for={{year, year_analyses} <- group_by_year(@analyses)}>
            <button
              phx-click="toggle_year"
              phx-value-year={year}
              class="flex items-center gap-2 mb-2 sm:mb-3 group cursor-pointer"
            >
              <.icon
                name="hero-chevron-down"
                class={[
                  "size-4 opacity-40 group-hover:opacity-70 transition-transform duration-250 ease-out",
                  MapSet.member?(@collapsed_years, year) && "-rotate-90"
                ]}
              />
              <h3 class="text-lg font-bold">{year}</h3>
              <span class="badge badge-sm badge-ghost">{length(year_analyses)}</span>
            </button>

            <div class={[
              "grid transition-[grid-template-rows] duration-250 ease-out",
              if(MapSet.member?(@collapsed_years, year),
                do: "grid-rows-[0fr]",
                else: "grid-rows-[1fr]"
              )
            ]}>
              <div class="overflow-hidden">
                <div class="space-y-3 sm:space-y-4 ml-2 sm:ml-6">
                  <div :for={analysis <- year_analyses} class="card bg-base-200 overflow-hidden">
                    <%!-- New format --%>
                    <div :if={is_new_format?(analysis)} class="p-3 sm:p-5">
                      <%!-- Header (always visible, clickable to toggle) --%>
                      <div
                        class="flex items-start justify-between gap-2 sm:gap-3 cursor-pointer"
                        phx-click="toggle_analysis"
                        phx-value-id={analysis.id}
                      >
                        <div class="flex-1 min-w-0">
                          <div class="flex items-center gap-2 sm:gap-3 mb-1">
                            <.icon
                              name="hero-chevron-down"
                              class={[
                                "size-3.5 opacity-40 shrink-0 transition-transform duration-200",
                                !MapSet.member?(@expanded_analyses, analysis.id) && "-rotate-90"
                              ]}
                            />
                            <span class={[
                              "inline-flex items-center justify-center w-9 h-9 sm:w-10 sm:h-10 rounded-lg text-xs sm:text-sm font-bold border shrink-0",
                              score_color(analysis.result_json["nota"])
                            ]}>
                              {format_score(analysis.result_json["nota"])}
                            </span>
                            <div class="min-w-0">
                              <h4
                                class="font-semibold text-xs sm:text-sm truncate"
                                title={analysis.result_json["titulo"]}
                              >
                                {analysis.result_json["titulo"]}
                              </h4>
                              <div class="flex flex-wrap items-center gap-1 mt-0.5">
                                <span class="text-[10px] sm:text-xs opacity-40">
                                  {format_datetime_br(analysis.inserted_at)}
                                </span>
                                <span
                                  :if={
                                    analysis.filters_json["month"] &&
                                      analysis.filters_json["month"] != 0
                                  }
                                  class="badge badge-xs badge-ghost"
                                >
                                  {Banking.month_name(analysis.filters_json["month"])}
                                </span>
                                <span
                                  :if={analysis.filters_json["month"] == 0}
                                  class="badge badge-xs badge-ghost"
                                >
                                  Ano todo
                                </span>
                                <span
                                  :if={
                                    analysis.filters_json["bank"] &&
                                      analysis.filters_json["bank"] != "all"
                                  }
                                  class="badge badge-xs badge-ghost"
                                >
                                  {String.capitalize(analysis.filters_json["bank"])}
                                </span>
                                <span
                                  :if={source_label(analysis.filters_json["statement_type"])}
                                  class="badge badge-xs badge-ghost"
                                >
                                  {source_label(analysis.filters_json["statement_type"])}
                                </span>
                                <span
                                  :if={type_label(analysis.filters_json["type"])}
                                  class="badge badge-xs badge-ghost"
                                >
                                  {type_label(analysis.filters_json["type"])}
                                </span>
                              </div>
                            </div>
                          </div>
                          <p
                            :if={analysis.prompt && analysis.prompt != ""}
                            class="text-xs opacity-30 italic mt-1 truncate ml-11 sm:ml-13"
                            title={analysis.prompt}
                          >
                            "{analysis.prompt}"
                          </p>
                        </div>
                        <button
                          phx-click="confirm_delete"
                          phx-value-id={analysis.id}
                          class="btn btn-ghost btn-xs text-error shrink-0 opacity-40 hover:opacity-100"
                        >
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      </div>

                      <%!-- Collapsible body --%>
                      <div class={[
                        "grid transition-[grid-template-rows] duration-250 ease-out",
                        if(MapSet.member?(@expanded_analyses, analysis.id),
                          do: "grid-rows-[1fr]",
                          else: "grid-rows-[0fr]"
                        )
                      ]}>
                        <div class="overflow-hidden">
                          <div class="mt-3">
                            <p class="text-xs sm:text-sm opacity-80 mb-3 sm:mb-4">
                              {analysis.result_json["resumo"]}
                            </p>

                            <div class="space-y-1.5 sm:space-y-2 mb-3 sm:mb-4">
                              <div
                                :for={ponto <- analysis.result_json["pontos"] || []}
                                class="flex items-start gap-2 text-xs sm:text-sm"
                              >
                                <.icon
                                  name={elem(ponto_icon(ponto["tipo"]), 0)}
                                  class={"size-4 shrink-0 mt-0.5 #{elem(ponto_icon(ponto["tipo"]), 1)}"}
                                />
                                <span class="opacity-80">{ponto["texto"]}</span>
                              </div>
                            </div>

                            <div
                              :if={analysis.result_json["alerta"]}
                              class="alert alert-warning text-xs sm:text-sm py-2 mb-3"
                            >
                              <.icon name="hero-exclamation-triangle" class="size-4" />
                              <span>{analysis.result_json["alerta"]}</span>
                            </div>

                            <div
                              :if={analysis.result_json["resposta"]}
                              class="bg-primary/5 border border-primary/10 rounded-lg p-2.5 sm:p-3"
                            >
                              <div class="flex items-center gap-1.5 mb-1">
                                <.icon
                                  name="hero-chat-bubble-left-right"
                                  class="size-3.5 text-primary"
                                />
                                <span class="text-xs font-medium text-primary">Resposta</span>
                              </div>
                              <p class="text-xs sm:text-sm opacity-80">
                                {analysis.result_json["resposta"]}
                              </p>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>

                    <%!-- Legacy format (old analyses) --%>
                    <div :if={!is_new_format?(analysis)} class="p-3 sm:p-5">
                      <%!-- Header (always visible, clickable to toggle) --%>
                      <div
                        class="flex items-start justify-between cursor-pointer"
                        phx-click="toggle_analysis"
                        phx-value-id={analysis.id}
                      >
                        <div>
                          <div class="flex items-center gap-2 mb-1">
                            <.icon
                              name="hero-chevron-down"
                              class={[
                                "size-3.5 opacity-40 shrink-0 transition-transform duration-200",
                                !MapSet.member?(@expanded_analyses, analysis.id) && "-rotate-90"
                              ]}
                            />
                            <.icon name="hero-sparkles" class="size-4 text-primary" />
                            <span class="font-semibold text-xs sm:text-sm">
                              {format_datetime_br(analysis.inserted_at)}
                            </span>
                          </div>
                          <div class="flex flex-wrap gap-1 ml-5">
                            <span
                              :if={analysis.filters_json["year"]}
                              class="badge badge-xs badge-ghost"
                            >
                              {analysis.filters_json["year"]}
                            </span>
                            <span
                              :if={
                                analysis.filters_json["month"] && analysis.filters_json["month"] != 0
                              }
                              class="badge badge-xs badge-ghost"
                            >
                              {Banking.month_name(analysis.filters_json["month"])}
                            </span>
                            <span
                              :if={
                                analysis.filters_json["bank"] &&
                                  analysis.filters_json["bank"] != "all"
                              }
                              class="badge badge-xs badge-ghost"
                            >
                              {String.capitalize(analysis.filters_json["bank"])}
                            </span>
                          </div>
                        </div>
                        <button
                          phx-click="confirm_delete"
                          phx-value-id={analysis.id}
                          class="btn btn-ghost btn-xs text-error opacity-40 hover:opacity-100"
                        >
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      </div>

                      <%!-- Collapsible body --%>
                      <div class={[
                        "grid transition-[grid-template-rows] duration-250 ease-out",
                        if(MapSet.member?(@expanded_analyses, analysis.id),
                          do: "grid-rows-[1fr]",
                          else: "grid-rows-[0fr]"
                        )
                      ]}>
                        <div class="overflow-hidden">
                          <div class="mt-3">
                            <p class="text-xs sm:text-sm mb-3 opacity-80">
                              {analysis.result_json["resumo"]}
                            </p>

                            <div class="space-y-2 mb-3">
                              <div
                                :for={insight <- analysis.result_json["insights"] || []}
                                class="flex items-start gap-2 text-xs sm:text-sm"
                              >
                                <.icon
                                  name="hero-light-bulb"
                                  class="size-4 text-warning shrink-0 mt-0.5"
                                />
                                <span class="opacity-80">{insight}</span>
                              </div>
                            </div>

                            <div
                              :if={analysis.result_json["alerta"]}
                              class="alert alert-warning text-xs sm:text-sm py-2 mb-3"
                            >
                              <.icon name="hero-exclamation-triangle" class="size-4" />
                              <span>{analysis.result_json["alerta"]}</span>
                            </div>

                            <div
                              :if={analysis.result_json["dica"]}
                              class="flex items-start gap-2 text-xs sm:text-sm bg-success/10 rounded-lg p-3"
                            >
                              <.icon
                                name="hero-check-circle"
                                class="size-4 text-success shrink-0 mt-0.5"
                              />
                              <span class="opacity-80">{analysis.result_json["dica"]}</span>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- API Key Alert Modal --%>
        <dialog
          :if={@show_api_key_alert}
          class="modal modal-open"
          phx-window-keydown="dismiss_api_alert"
          phx-key="Escape"
        >
          <div class="modal-box">
            <h3 class="text-lg font-bold">Provedor de IA não configurado</h3>
            <p class="py-4 opacity-70">
              Para usar funcionalidades de IA, você precisa cadastrar um provedor de IA (Gemini, OpenAI, Claude ou compatível).
            </p>
            <ol class="list-decimal list-inside text-sm opacity-70 space-y-1 mb-4">
              <li>
                Crie uma chave no provedor que preferir:
                <a href="https://aistudio.google.com/apikey" target="_blank" class="link link-primary">
                  Google Gemini
                </a>
                ·
                <a
                  href="https://platform.openai.com/api-keys"
                  target="_blank"
                  class="link link-primary"
                >
                  OpenAI
                </a>
                ·
                <a
                  href="https://console.anthropic.com/settings/keys"
                  target="_blank"
                  class="link link-primary"
                >
                  Claude
                </a>
              </li>
              <li>Cadastre o provedor em Configurações → LLM</li>
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

        <%!-- Delete Confirmation Modal --%>
        <dialog
          :if={@delete_target}
          id="delete_analysis_modal"
          class="modal modal-open"
          phx-window-keydown="cancel_delete"
          phx-key="Escape"
        >
          <div class="modal-box">
            <h3 class="text-lg font-bold">Remover análise</h3>
            <p class="py-4 opacity-70">
              Tem certeza que deseja remover esta análise? Esta ação é permanente.
            </p>
            <div class="modal-action">
              <button phx-click="cancel_delete" class="btn btn-ghost">Cancelar</button>
              <button phx-click="delete_analysis" class="btn btn-error">Remover</button>
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
end
