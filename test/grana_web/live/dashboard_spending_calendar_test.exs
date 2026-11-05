defmodule GranaWeb.DashboardSpendingCalendarTest do
  use GranaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Grana.BankingFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    transactions_fixture(user, [
      %{date: ~D[2026-03-02], description: "PADARIA", amount: "-50.00"},
      %{date: ~D[2026-03-10], description: "MERCADO", amount: "-200.00"},
      %{date: ~D[2026-03-28], description: "FARMACIA", amount: "-100.00"},
      %{date: ~D[2025-07-15], description: "VIAGEM", amount: "-400.00"}
    ])

    :ok
  end

  defp cell(view, label), do: element(view, ~s|#spending-calendar [data-day-date="#{label}"]|)

  test "the month turns into a calendar shaded by the spending of each day", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")
    assert has_element?(view, "#daily-chart")
    refute has_element?(view, "#spending-calendar")

    view |> element("#daily-view-calendar") |> render_click()
    assert has_element?(view, "#daily-view-calendar[aria-pressed=true]")
    refute has_element?(view, "#daily-chart")
    assert has_element?(view, "#spending-calendar .ui-heat-column", "Dom")

    # March 2026 starts on a Sunday: no leading blanks, 31 days over 5 weeks.
    html = view |> element("#spending-calendar") |> render()
    document = LazyHTML.from_fragment(html)
    assert document |> LazyHTML.query(".ui-heat-row:not(.ui-heat-head)") |> Enum.count() == 5
    assert document |> LazyHTML.query(".ui-heat-blank") |> Enum.count() == 4
    assert document |> LazyHTML.query(".ui-heat-cell:not(.ui-heat-blank)") |> Enum.count() == 31

    assert view |> cell("10/03/2026") |> render() =~ "--heat: 1.0"
    assert view |> cell("02/03/2026") |> render() =~ "--heat: 0.25"
    assert view |> cell("10/03/2026") |> render() =~ "is-strong"
    refute view |> cell("28/03/2026") |> render() =~ "is-strong"
    assert view |> cell("10/03/2026") |> render() =~ "date_from=2026-03-10"
    assert view |> cell("11/03/2026") |> render() =~ "ui-heat-empty"

    view |> element("#daily-view-bars") |> render_click()
    assert has_element?(view, "#daily-chart")
  end

  test "the year shows its months and all years one row per year", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")
    view |> element("#daily-view-calendar") |> render_click()

    render_click(view, "select_month", %{"month" => "all"})
    assert has_element?(view, "#monthly-view-calendar[aria-pressed=true]")
    assert has_element?(view, "#spending-calendar .ui-heat-column", "Jan")
    assert view |> cell("Mar/2026") |> render() =~ "--heat: 1.0"
    assert view |> cell("Jan/2026") |> render() =~ "ui-heat-empty"

    render_click(view, "select_view_total", %{})
    assert has_element?(view, "#yearly-view-calendar[aria-pressed=true]")
    assert has_element?(view, "#spending-calendar .ui-heat-label", "2025")
    assert has_element?(view, "#spending-calendar .ui-heat-label", "2026")
    assert view |> cell("Jul/2025") |> render() =~ "--heat: 1.0"
    assert view |> cell("Mar/2026") |> render() =~ "--heat: 0.875"
  end

  test "days and months still to come stay dim", %{conn: conn, user: user} do
    today = Grana.LocalTime.today()
    transactions_fixture(user, [%{date: today, description: "HOJE", amount: "-10.00"}])

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    render_click(view, "select_year", %{"year" => to_string(today.year)})
    render_click(view, "select_month", %{"month" => to_string(today.month)})
    view |> element("#daily-view-calendar") |> render_click()

    tomorrow = Date.add(today, 1)

    if tomorrow.month == today.month do
      label = Calendar.strftime(tomorrow, "%d/%m/%Y")
      assert has_element?(view, ~s|#spending-calendar .ui-heat-future[aria-label="#{label}"]|)
    end

    assert view |> cell(Calendar.strftime(today, "%d/%m/%Y")) |> render() =~ "--heat: 1.0"
  end
end
