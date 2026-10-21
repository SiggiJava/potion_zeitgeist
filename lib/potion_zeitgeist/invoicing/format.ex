defmodule PotionZeitgeist.Invoicing.Format do
  @moduledoc """
  German formatting for invoice documents: dates, months, amounts, hours and
  percentages. The app UI is English, but invoices go to German clients.
  """

  @months ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)

  @doc "`~D[2026-10-21]` becomes \"21.10.2026\"."
  def date(nil), do: ""
  def date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")

  @doc "`~D[2026-10-01]` becomes \"Oktober 2026\"."
  def month(%Date{} = date), do: "#{Enum.at(@months, date.month - 1)} #{date.year}"

  @doc "\"01.10.2026 – 31.10.2026\", or a single date when both are equal."
  def period(%Date{} = first, %Date{} = last) do
    if Date.compare(first, last) == :eq,
      do: date(first),
      else: "#{date(first)} – #{date(last)}"
  end

  def period(_first, _last), do: ""

  @doc "`Decimal.new(\"1234.5\")` becomes \"1.234,50 €\"."
  def money(nil), do: ""
  def money(amount), do: number(amount, 2) <> " €"

  @doc "Hours with two decimals: \"32,50\"."
  def hours(nil), do: ""
  def hours(hours), do: number(hours, 2)

  @doc "Minutes as hours and minutes: 125 becomes \"2:05\"."
  def duration(minutes) when is_integer(minutes) do
    "#{div(minutes, 60)}:#{minutes |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  @doc "`Decimal.new(\"19\")` becomes \"19 %\", `Decimal.new(\"7.5\")` \"7,5 %\"."
  def percent(nil), do: ""

  def percent(rate) do
    text =
      rate
      |> Decimal.new()
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)
      |> String.replace(".", ",")

    text <> " %"
  end

  @doc "Decimal number with German separators and a fixed number of decimals."
  def number(value, places) do
    rounded = value |> Decimal.new() |> Decimal.round(places, :half_up)
    sign = if Decimal.negative?(rounded), do: "-", else: ""

    [int, frac] =
      case rounded |> Decimal.abs() |> Decimal.to_string(:normal) |> String.split(".") do
        [int] -> [int, ""]
        [int, frac] -> [int, frac]
      end

    frac = String.pad_trailing(frac, places, "0")
    int = group_thousands(int)

    if places > 0, do: "#{sign}#{int},#{frac}", else: "#{sign}#{int}"
  end

  defp group_thousands(digits) do
    digits
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(".", &Enum.join/1)
    |> String.reverse()
  end
end
