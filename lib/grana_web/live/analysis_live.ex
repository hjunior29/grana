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
      nota >= 8 -> "ui-money-receita bg-(--ui-receita)/15 border-(--ui-receita)/30"
      nota >= 6 -> "text-info bg-info/15 border-info/30"
      nota >= 4 -> "text-warning bg-warning/15 border-warning/30"
      true -> "ui-money-despesa bg-(--ui-despesa)/15 border-(--ui-despesa)/30"
    end
  end

  defp score_color(_), do: "text-info bg-info/15 border-info/30"

  defp ponto_icon("positivo"), do: {"hero-check-circle", "ui-money-receita"}
  defp ponto_icon("negativo"), do: {"hero-x-circle", "ui-money-despesa"}
  defp ponto_icon("dica"), do: {"hero-light-bulb", "text-warning"}
  defp ponto_icon(_), do: {"hero-minus-circle", "ui-text-tertiary"}

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
        <.page_header title="Análise" subtitle="Insights inteligentes sobre suas finanças" />

        <%!-- Filters --%>
        <.filter_bar :if={@available_years != []} id="analysis-filters">
          <.period_filter
            years={@available_years}
            selected_year={@filters.year}
            months={months_for_year(@available_months, @filters.year)}
            selected_month={if @filters.month != 0, do: @filters.month}
            all_months_active={@filters.month == 0}
            all_months_label="Ano"
          />
          <.bank_filter banks={@banks} selected={@filters.bank} />
          <.source_filter selected={@filters.statement_type} event="select_source" param="source" />
          <.movement_filter selected={@filters.type} />
        </.filter_bar>

        <%!-- Prompt + Analyze --%>
        <div class="card bg-base-200 mb-6 p-4 sm:mb-8 sm:p-6">
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

            <div class="mb-3 flex flex-wrap gap-1.5">
              <.chip
                :for={
                  suggestion <- [
                    "Onde posso economizar?",
                    "Qual categoria cresceu mais?",
                    "Como estão meus gastos fixos?",
                    "Resumo do mês"
                  ]
                }
                class="ui-chip-outline"
                phx-click="set_chip"
                phx-value-text={suggestion}
              >
                {suggestion}
              </.chip>
            </div>

            <.button
              id="analyze-button"
              variant="primary"
              size="sm"
              icon={if !@loading, do: "hero-sparkles"}
              class="w-full sm:w-auto"
              disabled={@loading}
            >
              {if @loading, do: "Analisando…", else: "Analisar com IA"}
            </.button>
          </.form>
        </div>

        <%!-- Loading --%>
        <div :if={@loading} id="analysis-loading" class="card bg-base-200 mb-6 p-4 sm:p-6">
          <div class="flex items-center gap-3">
            <.tag kind="pendente">Em andamento</.tag>
            <span class="ui-body ui-text-secondary">Analisando seus dados com IA…</span>
          </div>
        </div>

        <%!-- Empty State --%>
        <.empty_state
          :if={@analyses == [] and !@loading}
          id="analysis-empty"
          icon="hero-sparkles"
          title="Nenhuma análise ainda"
          text={~s(Configure os filtros e clique em "Analisar com IA".)}
        />

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
                  "size-4 ui-text-tertiary group-hover:text-base-content transition-transform duration-250 ease-out",
                  MapSet.member?(@collapsed_years, year) && "-rotate-90"
                ]}
              />
              <h3 class="text-lg font-bold">{year}</h3>
              <span class="ui-tag ui-tag-neutro">{length(year_analyses)}</span>
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
                                "size-3.5 ui-text-tertiary shrink-0 transition-transform duration-200",
                                !MapSet.member?(@expanded_analyses, analysis.id) && "-rotate-90"
                              ]}
                            />
                            <span class={[
                              "inline-flex items-center justify-center w-9 h-9 sm:w-10 sm:h-10 ui-rounded-box text-xs sm:text-sm font-bold border shrink-0",
                              score_color(analysis.result_json["nota"])
                            ]}>
                              {format_score(analysis.result_json["nota"])}
                            </span>
                            <div class="min-w-0">
                              <h4
                                class="font-semibold text-xs sm:text-sm truncate"
                                title={analysis.result_json["titulo"]}
                              >
                                <.private_text text={analysis.result_json["titulo"]} />
                              </h4>
                              <div class="flex flex-wrap items-center gap-1 mt-0.5">
                                <span class="ui-caption sm:text-xs">
                                  {format_datetime_br(analysis.inserted_at)}
                                </span>
                                <span
                                  :if={
                                    analysis.filters_json["month"] &&
                                      analysis.filters_json["month"] != 0
                                  }
                                  class="ui-tag ui-tag-neutro"
                                >
                                  {Banking.month_name(analysis.filters_json["month"])}
                                </span>
                                <span
                                  :if={analysis.filters_json["month"] == 0}
                                  class="ui-tag ui-tag-neutro"
                                >
                                  Ano todo
                                </span>
                                <span
                                  :if={
                                    analysis.filters_json["bank"] &&
                                      analysis.filters_json["bank"] != "all"
                                  }
                                  class="ui-tag ui-tag-neutro"
                                >
                                  {String.capitalize(analysis.filters_json["bank"])}
                                </span>
                                <span
                                  :if={source_label(analysis.filters_json["statement_type"])}
                                  class="ui-tag ui-tag-neutro"
                                >
                                  {source_label(analysis.filters_json["statement_type"])}
                                </span>
                                <span
                                  :if={type_label(analysis.filters_json["type"])}
                                  class="ui-tag ui-tag-neutro"
                                >
                                  {type_label(analysis.filters_json["type"])}
                                </span>
                              </div>
                            </div>
                          </div>
                          <p
                            :if={analysis.prompt && analysis.prompt != ""}
                            class="text-xs ui-text-tertiary italic mt-1 truncate ml-11 sm:ml-13"
                            title={analysis.prompt}
                          >
                            "{analysis.prompt}"
                          </p>
                        </div>
                        <button
                          phx-click="confirm_delete"
                          phx-value-id={analysis.id}
                          class="btn btn-ghost btn-xs text-error shrink-0"
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
                            <p class="text-xs sm:text-sm ui-text-secondary mb-3 sm:mb-4">
                              <.private_text text={analysis.result_json["resumo"]} />
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
                                <span class="ui-text-secondary">
                                  <.private_text text={ponto["texto"]} />
                                </span>
                              </div>
                            </div>

                            <.notice :if={analysis.result_json["alerta"]} tone={:warning} class="mb-3">
                              <.private_text text={analysis.result_json["alerta"]} />
                            </.notice>

                            <div
                              :if={analysis.result_json["resposta"]}
                              class="bg-primary/5 border border-primary/10 ui-rounded-box p-2.5 sm:p-3"
                            >
                              <div class="flex items-center gap-1.5 mb-1">
                                <.icon
                                  name="hero-chat-bubble-left-right"
                                  class="size-3.5 text-primary"
                                />
                                <span class="text-xs font-medium text-primary">Resposta</span>
                              </div>
                              <p class="text-xs sm:text-sm ui-text-secondary">
                                <.private_text text={analysis.result_json["resposta"]} />
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
                                "size-3.5 ui-text-tertiary shrink-0 transition-transform duration-200",
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
                              class="ui-tag ui-tag-neutro"
                            >
                              {analysis.filters_json["year"]}
                            </span>
                            <span
                              :if={
                                analysis.filters_json["month"] && analysis.filters_json["month"] != 0
                              }
                              class="ui-tag ui-tag-neutro"
                            >
                              {Banking.month_name(analysis.filters_json["month"])}
                            </span>
                            <span
                              :if={
                                analysis.filters_json["bank"] &&
                                  analysis.filters_json["bank"] != "all"
                              }
                              class="ui-tag ui-tag-neutro"
                            >
                              {String.capitalize(analysis.filters_json["bank"])}
                            </span>
                          </div>
                        </div>
                        <button
                          phx-click="confirm_delete"
                          phx-value-id={analysis.id}
                          class="btn btn-ghost btn-xs text-error"
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
                            <p class="text-xs sm:text-sm mb-3 ui-text-secondary">
                              <.private_text text={analysis.result_json["resumo"]} />
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
                                <span class="ui-text-secondary">
                                  <.private_text text={insight} />
                                </span>
                              </div>
                            </div>

                            <.notice :if={analysis.result_json["alerta"]} tone={:warning} class="mb-3">
                              <.private_text text={analysis.result_json["alerta"]} />
                            </.notice>

                            <div
                              :if={analysis.result_json["dica"]}
                              class="flex items-start gap-2 text-xs sm:text-sm bg-(--ui-receita)/10 ui-rounded-box p-3"
                            >
                              <.icon
                                name="hero-check-circle"
                                class="ui-money-receita size-4 shrink-0 mt-0.5"
                              />
                              <span class="ui-text-secondary">
                                <.private_text text={analysis.result_json["dica"]} />
                              </span>
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

        <.ai_required_modal
          :if={@show_api_key_alert}
          reason="A análise usa IA para ler os seus dados e gerar os insights."
        />

        <.confirm_modal
          :if={@delete_target}
          id="delete_analysis_modal"
          open
          title="Remover análise"
          confirm="Remover"
          loading="Removendo…"
          on_confirm={JS.push("delete_analysis")}
          on_cancel={JS.push("cancel_delete")}
        >
          Tem certeza que deseja remover esta análise? Esta ação é permanente.
        </.confirm_modal>
      </div>
    </Layouts.app>
    """
  end
end
