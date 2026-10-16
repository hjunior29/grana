defmodule GranaWeb.AnalysisComponents do
  @moduledoc """
  The period analysis on the dashboard (`Grana.Analyses`): an accordion below the
  filters with the AI's score, summary, points and alert for the selected month or
  year, and the button and model to analyze it (again).
  """
  use GranaWeb, :html

  alias Grana.Banking
  alias GranaWeb.AiComponents

  attr :analysis, :any, default: nil, doc: "`Grana.Banking.AIAnalysis` of the period"

  attr :status, :any,
    default: nil,
    doc: "nil, :loading, :current (nothing changed since the analysis) or {:error, message}"

  attr :open, :boolean, required: true
  attr :year, :integer, required: true
  attr :month, :integer, required: true, doc: "0 for the whole year"
  attr :filtered, :boolean, default: false, doc: "bank, source or movement filters active"
  attr :model_choices, :any, required: true
  attr :model_default, :any, default: nil
  attr :private_names, :any, default: nil

  def analysis_panel(assigns) do
    assigns = assign(assigns, :period, period_label(assigns.year, assigns.month))

    ~H"""
    <section id="analysis-panel" class="card bg-base-200 mb-6 overflow-hidden">
      <button
        id="analysis-toggle"
        type="button"
        class="group flex w-full cursor-pointer items-center gap-3 p-4 text-left sm:px-6"
        phx-click="set_preference"
        phx-value-analysis_open={to_string(!@open)}
        aria-expanded={to_string(@open)}
        aria-controls="analysis-body"
      >
        <span class="flex size-9 shrink-0 items-center justify-center ui-rounded-box bg-primary/10 text-primary">
          <.icon name="hero-sparkles" class="size-5" />
        </span>
        <span class="min-w-0 flex-1">
          <span class="ui-card-title block">Análise de {@period}</span>
          <span class="ui-help block truncate">{subtitle(@analysis, @status)}</span>
        </span>
        <.tag :if={@status == :loading} kind="pendente" class="shrink-0">Em andamento</.tag>
        <span
          :if={@analysis && @status != :loading}
          id="analysis-score"
          class={["ui-score shrink-0", score_class(@analysis.result_json["nota"])]}
        >
          {format_score(@analysis.result_json["nota"])}
        </span>
        <.icon
          name="hero-chevron-down"
          class={[
            "size-4 shrink-0 ui-text-tertiary transition-transform duration-250 ease-out group-hover:text-base-content",
            !@open && "-rotate-90"
          ]}
        />
      </button>

      <div
        id="analysis-body"
        class={[
          "grid transition-[grid-template-rows] duration-250 ease-out",
          if(@open, do: "grid-rows-[1fr]", else: "grid-rows-[0fr]")
        ]}
      >
        <div class="overflow-hidden">
          <div class="border-t border-base-content/5 px-4 pt-4 pb-4 sm:px-6 sm:pb-6">
            <p
              :if={@filtered}
              id="analysis-filters-note"
              class="ui-caption mb-3 flex items-center justify-end gap-1.5"
            >
              <.icon name="hero-funnel" class="size-3.5" />
              Feita sobre {@period} inteiro, sem os filtros de banco, fonte e tipo
            </p>

            <%= cond do %>
              <% @status == :loading -> %>
                <div id="analysis-loading" class="flex items-center gap-3 py-2">
                  <span class="loading loading-spinner loading-sm text-primary"></span>
                  <span class="ui-body ui-text-secondary">
                    Analisando {@period}… Pode sair desta tela: avisamos quando terminar.
                  </span>
                </div>
              <% @analysis -> %>
                <.analysis_body analysis={@analysis} private_names={@private_names} />
              <% true -> %>
                <p id="analysis-empty" class="ui-body ui-text-secondary">
                  Ainda não há análise de {@period}. A IA avalia receitas, despesas, onde dá para
                  otimizar e se foi um período bom, regular ou ruim.
                </p>
            <% end %>

            <.notice :if={match?({:error, _}, @status)} id="analysis-error" tone={:error} class="mt-4">
              {elem(@status, 1)}
            </.notice>

            <p :if={@status == :current} id="analysis-current" class="ui-help mt-4">
              Nada mudou em {@period} desde a última análise, então ela continua valendo.
            </p>

            <form
              id="analysis-form"
              phx-submit="analyze"
              class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-center"
            >
              <.button
                id="analyze-button"
                variant="primary"
                size="sm"
                icon="hero-sparkles"
                class="w-full sm:w-auto"
                disabled={@status == :loading}
              >
                {if @analysis, do: "Analisar de novo", else: "Analisar com IA"}
              </.button>
              <AiComponents.model_picker
                id="analysis-model"
                choices={@model_choices}
                default={@model_default}
                disabled={@status == :loading}
              />
            </form>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :analysis, :map, required: true
  attr :private_names, :any, default: nil

  defp analysis_body(assigns) do
    ~H"""
    <div id="analysis-content">
      <h3 class="font-semibold">
        <.private_text names={@private_names} text={@analysis.result_json["titulo"]} />
      </h3>
      <p class="ui-body ui-text-secondary mt-1 mb-4">
        <.private_text names={@private_names} text={@analysis.result_json["resumo"]} />
      </p>

      <ul class="space-y-2 mb-4">
        <li
          :for={point <- @analysis.result_json["pontos"] || []}
          class="flex items-start gap-2 ui-body"
        >
          <.icon
            name={elem(point_icon(point["tipo"]), 0)}
            class={["size-4 shrink-0 mt-0.5", elem(point_icon(point["tipo"]), 1)]}
          />
          <span class="ui-text-secondary">
            <.private_text names={@private_names} text={point["texto"]} />
          </span>
        </li>
      </ul>

      <.notice :if={@analysis.result_json["alerta"]} tone={:warning}>
        <.private_text names={@private_names} text={@analysis.result_json["alerta"]} />
      </.notice>
    </div>
    """
  end

  defp subtitle(_analysis, :loading), do: "A IA está lendo os dados do período."

  defp subtitle(%{inserted_at: at, ai_model: model}, _status),
    do: "Analisada em #{format_datetime(at)}#{if model, do: " · #{model}", else: ""}"

  defp subtitle(nil, _status),
    do: "Receitas, despesas, onde otimizar e como foi o período, com IA."

  defp period_label(year, 0), do: to_string(year)
  defp period_label(year, month), do: "#{String.downcase(Banking.month_name(month))} de #{year}"

  defp format_datetime(datetime) do
    datetime |> DateTime.add(-3, :hour) |> Calendar.strftime("%d/%m/%Y às %H:%M")
  end

  defp score_class(score) when is_number(score) do
    cond do
      score >= 8 -> "ui-score-good"
      score >= 6 -> "ui-score-ok"
      score >= 4 -> "ui-score-warn"
      true -> "ui-score-bad"
    end
  end

  defp score_class(score) when is_binary(score) do
    case Float.parse(score) do
      {number, _} -> score_class(number)
      :error -> "ui-score-ok"
    end
  end

  defp score_class(_score), do: "ui-score-ok"

  defp format_score(score) when is_float(score), do: score |> Float.round(1) |> to_string()
  defp format_score(score) when is_integer(score), do: "#{score}.0"
  defp format_score(score) when is_binary(score), do: score
  defp format_score(_score), do: "—"

  defp point_icon("positivo"), do: {"hero-check-circle", "ui-money-receita"}
  defp point_icon("negativo"), do: {"hero-x-circle", "ui-money-despesa"}
  defp point_icon("dica"), do: {"hero-light-bulb", "text-warning"}
  defp point_icon(_kind), do: {"hero-minus-circle", "ui-text-tertiary"}
end
