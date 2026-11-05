defmodule GranaWeb.SpendingCalendar do
  @moduledoc """
  Calendar view of the spending charts on the dashboard: a grid of days (month), months
  (year) or years by month (all years), each cell shaded towards the expense red by how
  much was spent compared with the other cells. Amounts only show on hover. In a month
  there is also the pace view (`pace_chart/1`), the spending accumulated day by day.
  """
  use GranaWeb, :html

  attr :id, :string, required: true
  attr :view, :string, required: true, values: ~w(bars calendar pace)
  attr :pace, :boolean, default: false, doc: "oferece o ritmo do mês (só na visão de um mês)"

  def view_toggle(assigns) do
    ~H"""
    <div id={@id} class="ui-view-toggle" role="group" aria-label="Forma do gráfico">
      <button
        type="button"
        id={"#{@id}-bars"}
        class={["ui-view-toggle-btn", @view == "bars" && "is-active"]}
        phx-click="set_spending_view"
        phx-value-view="bars"
        aria-pressed={to_string(@view == "bars")}
        title="Barras"
      >
        <.icon name="hero-chart-bar" class="size-4" />
      </button>
      <button
        type="button"
        id={"#{@id}-calendar"}
        class={["ui-view-toggle-btn", @view == "calendar" && "is-active"]}
        phx-click="set_spending_view"
        phx-value-view="calendar"
        aria-pressed={to_string(@view == "calendar")}
        title="Calendário"
      >
        <.icon name="hero-calendar-days" class="size-4" />
      </button>
      <button
        :if={@pace}
        type="button"
        id={"#{@id}-pace"}
        class={["ui-view-toggle-btn", @view == "pace" && "is-active"]}
        phx-click="set_spending_view"
        phx-value-view="pace"
        aria-pressed={to_string(@view == "pace")}
        title="Ritmo"
      >
        <.icon name="hero-arrow-trending-up" class="size-4" />
      </button>
    </div>
    """
  end

  @width 700
  @height 200
  @pad_x 8
  @pad_top 16
  @pad_bottom 26

  @doc """
  Pace of the month: what was spent so far, day by day, as a filled curve in the primary
  color, over the previous month as a dashed reference line. `current` and `previous` are
  the cumulative totals per day (`[{day, float}]`); `until` is the last day drawn for the
  current month (today in the current month), marked with a dot.
  """
  attr :id, :string, required: true
  attr :current, :list, required: true
  attr :previous, :list, required: true
  attr :days, :integer, required: true, doc: "days in the month"
  attr :until, :integer, required: true
  attr :today, :boolean, default: false, doc: "the month is the current one"
  attr :urls, :map, default: %{}, doc: "day => transactions from day 1 to it"
  attr :month_label, :string, required: true

  def pace_chart(assigns) do
    span = max(assigns.days, length(assigns.previous))
    max_value = Enum.max([1.0 | Enum.map(assigns.current ++ assigns.previous, &elem(&1, 1))])
    scale = %{span: span, max: max_value}
    current = Enum.filter(assigns.current, fn {day, _} -> day <= assigns.until end)
    last = List.last(current)

    assigns =
      assign(assigns,
        line: line_path(current, scale),
        area: area_path(current, scale),
        reference: line_path(assigns.previous, scale),
        last: last && point(last, scale),
        current: current,
        scale: scale,
        ticks: Enum.uniq([1, 5, 10, 15, 20, 25, assigns.days]),
        slot: (@width - 2 * @pad_x) / max(span - 1, 1)
      )

    ~H"""
    <div id={@id} phx-hook="SpendingCalendar" class="ui-pace">
      <svg
        viewBox={"0 0 #{width()} #{height()}"}
        class="ui-pace-svg"
        role="img"
        aria-label={"Gasto acumulado de #{@month_label} comparado com o mês anterior"}
      >
        <line
          x1={pad_x()}
          x2={width() - pad_x()}
          y1={baseline()}
          y2={baseline()}
          class="ui-pace-axis"
        />
        <path :if={@reference} d={@reference} class="ui-pace-reference" />
        <path :if={@area} d={@area} class="ui-pace-area" />
        <path :if={@line} d={@line} class="ui-pace-line" />
        <circle
          :if={@today && @last}
          cx={elem(@last, 0)}
          cy={elem(@last, 1)}
          r="5"
          class="ui-pace-dot"
        />
        <text
          :for={day <- @ticks}
          x={elem(point({day, 0}, @scale), 0)}
          y={height() - 6}
          text-anchor="middle"
          class="ui-pace-tick"
        >
          {day}
        </text>
        <rect
          :for={{day, value} <- @current}
          x={elem(point({day, 0}, @scale), 0) - @slot / 2}
          y="0"
          width={@slot}
          height={baseline()}
          class="ui-pace-hit"
          data-day-date={"Até o dia #{day}"}
          data-day-value={value}
          data-day-url={@urls[day]}
        />
      </svg>
    </div>
    """
  end

  defp width, do: @width
  defp height, do: @height
  defp pad_x, do: @pad_x
  defp baseline, do: @height - @pad_bottom

  defp point({day, value}, %{span: span, max: max}) do
    x = @pad_x + (day - 1) / max(span - 1, 1) * (@width - 2 * @pad_x)
    y = baseline() - value / max * (baseline() - @pad_top)
    {Float.round(x, 1), Float.round(y, 1)}
  end

  defp line_path([], _scale), do: nil

  defp line_path(points, scale) do
    points
    |> Enum.map(&point(&1, scale))
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {{x, y}, i} -> "#{if i == 0, do: "M", else: "L"} #{x} #{y}" end)
  end

  defp area_path([], _scale), do: nil

  defp area_path(points, scale) do
    {first_x, _} = point(hd(points), scale)
    {last_x, _} = point(List.last(points), scale)
    "#{line_path(points, scale)} L #{last_x} #{baseline()} L #{first_x} #{baseline()} Z"
  end

  attr :id, :string, required: true
  attr :columns, :list, required: true, doc: "header of each column"

  attr :rows, :list,
    required: true,
    doc: "`%{label:, cells: [%{kind:, label:, caption:, value:, intensity:, url:}]}`"

  attr :row_labels, :boolean, default: false

  def heat_grid(assigns) do
    ~H"""
    <div id={@id} phx-hook="SpendingCalendar" class="ui-heat">
      <div class="ui-heat-row ui-heat-head">
        <div :if={@row_labels} class="ui-heat-label"></div>
        <div :for={column <- @columns} class="ui-heat-column ui-caption">{column}</div>
      </div>
      <div :for={row <- @rows} class="ui-heat-row">
        <div :if={@row_labels} class="ui-heat-label ui-caption">{row.label}</div>
        <div
          :for={cell <- row.cells}
          class={["ui-heat-cell", "ui-heat-#{cell.kind}", strong?(cell) && "is-strong"]}
          style={cell.kind == :spend && "--heat: #{cell.intensity}"}
          data-day-date={cell.kind in [:spend, :empty] && cell.label}
          data-day-value={cell.kind == :spend && cell.value}
          data-day-url={cell.kind == :spend && cell.url}
          aria-label={cell.kind != :blank && cell.label}
        >
          <span :if={cell.caption} class="ui-heat-caption">{cell.caption}</span>
        </div>
      </div>
      <div class="ui-heat-legend ui-caption">
        <span>Menos</span>
        <span :for={heat <- [0.15, 0.4, 0.7, 1.0]} class="ui-heat-swatch" style={"--heat: #{heat}"}>
        </span>
        <span>Mais</span>
      </div>
    </div>
    """
  end

  defp strong?(%{kind: :spend, intensity: intensity}), do: intensity >= 0.55
  defp strong?(_cell), do: false
end
