defmodule GranaWeb.CalendarLive do
  @moduledoc """
  Heatmap do **calendário de importações** no estilo do "contributions graph" do GitHub:
  uma grade ano × mês onde cada quadrado é um mês, mais verde quanto mais tipos
  de documento (extrato, fatura, investimentos) têm dados naquele mês.

  Vai do ano do dado mais antigo até o mês atual.
  """
  use GranaWeb, :live_view

  alias Grana.Banking
  alias Grana.Investments

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    bank = Banking.coverage_by_statement_type(user_id)
    extrato = bank["extrato"]
    fatura = bank["fatura"]
    investimentos = Investments.coverage_months(user_id)

    upload_counts =
      merge_counts(
        Banking.upload_counts_by_month(user_id),
        Investments.upload_counts_by_month(user_id)
      )

    {:ok,
     socket
     |> assign(:page_title, "Calendário de Importações")
     |> build_grid(extrato, fatura, investimentos, upload_counts)}
  end

  defp build_grid(socket, extrato, fatura, investimentos, upload_counts) do
    all = extrato |> MapSet.union(fatura) |> MapSet.union(investimentos)

    if MapSet.size(all) == 0 do
      assign(socket, rows: [], has_data?: false)
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
                  {"Fatura", MapSet.member?(fatura, ym)},
                  {"Investimentos", MapSet.member?(investimentos, ym)}
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

      assign(socket, rows: rows, has_data?: true)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto scrollbar-gutter">
        <div class="mb-4 sm:mb-8">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Calendário de Importações</h1>
          <p class="text-xs sm:text-sm opacity-60 mt-1">
            Cada quadrado é um mês. Quanto mais verde, mais tipos de documento (extrato, fatura,
            investimentos) você importou naquele mês. Passe o mouse para ver o total de uploads.
          </p>
        </div>

        <div :if={!@has_data?} class="text-center py-16 opacity-60">
          <.icon name="hero-calendar-days" class="size-10 mx-auto mb-3 opacity-40" />
          <p>Ainda não há dados importados.</p>
          <p class="text-sm mt-1">
            Importe extratos, faturas ou investimentos em <.link navigate={~p"/upload"} class="link">Uploads</.link>.
          </p>
        </div>

        <div
          :if={@has_data?}
          id="calendar-heatmap"
          phx-hook="CalendarHeatmap"
          phx-update="ignore"
          class="card bg-base-200 w-full"
        >
          <div class="card-body p-5 sm:p-8">
            <div class="overflow-x-auto">
              <div class="w-max mx-auto">
                <%!-- Cabeçalho de meses --%>
                <div class="flex gap-1.5 mb-2">
                  <div class="w-12 shrink-0"></div>
                  <div
                    :for={m <- 1..12}
                    class="w-9 sm:w-11 shrink-0 text-center text-xs sm:text-sm font-medium opacity-60"
                  >
                    {month_label(m)}
                  </div>
                </div>

                <%!-- Linhas por ano --%>
                <div :for={row <- @rows} class="flex gap-1.5 items-center mb-1.5">
                  <div class="w-12 shrink-0 text-right pr-1 text-sm font-medium opacity-60">
                    {row.year}
                  </div>
                  <div
                    :for={cell <- row.cells}
                    class={[
                      "w-9 h-9 sm:w-11 sm:h-11 shrink-0 rounded-sm transition duration-150",
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
            </div>

            <%!-- Legenda --%>
            <div class="flex flex-wrap items-center justify-center gap-2 mt-6 text-sm opacity-60">
              <span class="mr-1">Menos</span>
              <div
                class="w-5 h-5 rounded-sm bg-base-300/70 border border-base-content/10"
                title="nenhum tipo"
              >
              </div>
              <div class="w-5 h-5 rounded-sm bg-[#86efac] border border-[#4ade80]" title="1 tipo">
              </div>
              <div class="w-5 h-5 rounded-sm bg-[#22c55e] border border-[#16a34a]" title="2 tipos">
              </div>
              <div class="w-5 h-5 rounded-sm bg-[#047857] border border-[#065f46]" title="3 tipos">
              </div>
              <span class="ml-1">Mais</span>
              <span class="ml-3 opacity-70">
                Verde cheio = extrato + fatura + investimentos no mês.
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Helpers ──

  defp cell_class(%{future?: true}), do: "bg-base-300/15 border border-base-content/5 opacity-60"
  defp cell_class(%{count: 0}), do: "bg-base-300/70 border border-base-content/10 cursor-help"
  defp cell_class(%{count: 1}), do: "bg-[#86efac] border border-[#4ade80] cursor-help"
  defp cell_class(%{count: 2}), do: "bg-[#22c55e] border border-[#16a34a] cursor-help"
  defp cell_class(%{count: 3}), do: "bg-[#047857] border border-[#065f46] cursor-help"

  defp cell_hover_class(%{future?: true}), do: "pointer-events-none"

  defp cell_hover_class(_cell),
    do:
      "hover:-translate-y-0.5 hover:scale-110 hover:brightness-110 hover:shadow-[0_10px_24px_rgba(0,0,0,0.24)] hover:ring-2 hover:ring-base-content/25"

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

  defp merge_counts(left, right) do
    Map.merge(left, right, fn _month, left_count, right_count -> left_count + right_count end)
  end

  defp pluralize_uploads(1), do: "1 upload"
  defp pluralize_uploads(count), do: "#{count} uploads"

  @month_abbr {"jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"}
  defp month_label(month), do: elem(@month_abbr, month - 1)
end
