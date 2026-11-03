defmodule PotionZeitgeist.Invoicing.FormatTest do
  use ExUnit.Case, async: true

  alias PotionZeitgeist.Invoicing.Format

  test "money uses German separators and the euro sign" do
    assert Format.money(Decimal.new("1234.5")) == "1.234,50 €"
    assert Format.money(Decimal.new("0")) == "0,00 €"
    assert Format.money(Decimal.new("1234567.891")) == "1.234.567,89 €"
    assert Format.money(Decimal.new("-12.5")) == "-12,50 €"
  end

  test "hours, percent and durations" do
    assert Format.hours(Decimal.new("32.5")) == "32,50"
    assert Format.percent(Decimal.new("19.00")) == "19 %"
    assert Format.percent(Decimal.new("7.5")) == "7,5 %"
    assert Format.duration(125) == "2:05"
    assert Format.duration(0) == "0:00"
  end

  test "quantities with as many decimals as they have" do
    assert Format.quantity(Decimal.new("2.500")) == "2,5"
    assert Format.quantity(Decimal.new("1250.000")) == "1.250"
    assert Format.quantity(Decimal.new("0.125")) == "0,125"
    assert Format.quantity(Decimal.new("99999.999")) == "99.999,999"
    assert Format.quantity(Decimal.new(3)) == "3"
    assert Format.quantity(nil) == ""
  end

  test "dates, months and periods" do
    assert Format.date(~D[2026-10-01]) == "01.10.2026"
    assert Format.month(~D[2026-03-01]) == "März 2026"
    assert Format.period(~D[2026-10-01], ~D[2026-10-31]) == "01.10.2026 – 31.10.2026"
    assert Format.period(~D[2026-10-01], ~D[2026-10-01]) == "01.10.2026"
  end
end
