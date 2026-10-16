defmodule GranaWeb.SpendingCalendar do
  @moduledoc """
  Calendar view of the spending charts on the dashboard: a grid of days (month), months
  (year) or years by month (all years), each cell shaded towards the expense red by how
  much was spent compared with the other cells. Amounts only show on hover.
  """
  use GranaWeb, :html

  attr :id, :string, required: true
  attr :view, :string, required: true, values: ~w(bars calendar)

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
    </div>
    """
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
