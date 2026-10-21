defmodule PotionZeitgeist.Invoicing.CalculationTest do
  use ExUnit.Case, async: true

  alias PotionZeitgeist.Invoicing.Calculation

  defp entry(project, clock_in, clock_out) do
    %{
      project_id: project && project.id,
      project: project,
      clock_in: NaiveDateTime.from_iso8601!(clock_in),
      clock_out: clock_out && NaiveDateTime.from_iso8601!(clock_out)
    }
  end

  @web %{id: 1, name: "Website"}
  @app %{id: 2, name: "App"}

  test "entries count with their duration rounded to full minutes" do
    assert Calculation.entry_minutes(entry(nil, "2026-10-01 08:00:00", "2026-10-01 08:20:29")) ==
             20

    assert Calculation.entry_minutes(entry(nil, "2026-10-01 08:00:00", "2026-10-01 08:20:30")) ==
             21

    assert Calculation.entry_minutes(entry(nil, "2026-10-01 08:00:00", nil)) == 0
  end

  test "groups completed entries by project, projects by name and no project last" do
    groups =
      Calculation.group_entries([
        entry(@web, "2026-10-01 08:00:00", "2026-10-01 10:00:00"),
        entry(nil, "2026-10-01 10:00:00", "2026-10-01 10:30:00"),
        entry(@app, "2026-10-02 08:00:00", "2026-10-02 09:00:00"),
        entry(@web, "2026-10-03 08:00:00", "2026-10-03 08:45:00"),
        entry(@web, "2026-10-04 08:00:00", nil)
      ])

    assert [
             %{key: "2", project_name: "App", minutes: 60},
             %{key: "1", project_name: "Website", minutes: 165, entries: [_, _]},
             %{key: "none", project_name: nil, minutes: 30}
           ] = groups
  end

  test "amounts come from hours rounded to two decimals" do
    groups =
      Calculation.group_entries([
        entry(@web, "2026-10-01 08:00:00", "2026-10-01 08:20:00"),
        entry(@web, "2026-10-02 08:00:00", "2026-10-02 08:20:00"),
        entry(@web, "2026-10-03 08:00:00", "2026-10-03 08:20:00")
      ])

    [item] = Calculation.build_items(groups, fn _ -> Decimal.new("85") end, fn _ -> nil end)

    assert item.minutes == 60
    assert Decimal.equal?(item.hours, Decimal.new("1.00"))
    assert Decimal.equal?(item.amount, Decimal.new("85.00"))
    assert item.description == "Website"

    [item] =
      Calculation.build_items(
        Calculation.group_entries([entry(nil, "2026-10-01 08:00:00", "2026-10-01 09:20:00")]),
        fn _ -> Decimal.new("90") end,
        fn _ -> "  " end
      )

    # 80 minutes are 1.33 hours, billed as 1.33 × 90.
    assert Decimal.equal?(item.hours, Decimal.new("1.33"))
    assert Decimal.equal?(item.amount, Decimal.new("119.70"))
    assert item.description == "Dienstleistungen"
  end

  test "items without a rate have no amount" do
    groups =
      Calculation.group_entries([entry(@web, "2026-10-01 08:00:00", "2026-10-01 09:00:00")])

    [item] = Calculation.build_items(groups, fn _ -> nil end, fn _ -> "Webdesign" end)

    assert item.amount == nil
    assert item.description == "Webdesign"
  end

  test "totals with and without VAT" do
    items = [
      %{minutes: 60, hours: Decimal.new("1.00"), amount: Decimal.new("85.00")},
      %{minutes: 30, hours: Decimal.new("0.50"), amount: Decimal.new("42.55")}
    ]

    totals = Calculation.totals(items, Decimal.new("19"))
    assert totals.minutes == 90
    assert Decimal.equal?(totals.hours, Decimal.new("1.50"))
    assert Decimal.equal?(totals.net, Decimal.new("127.55"))
    assert Decimal.equal?(totals.vat, Decimal.new("24.23"))
    assert Decimal.equal?(totals.gross, Decimal.new("151.78"))

    totals = Calculation.totals(items, 0)
    assert Decimal.equal?(totals.vat, 0)
    assert Decimal.equal?(totals.gross, Decimal.new("127.55"))
  end
end
