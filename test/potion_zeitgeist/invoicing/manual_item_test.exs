defmodule PotionZeitgeist.Invoicing.ManualItemTest do
  use ExUnit.Case, async: true

  alias PotionZeitgeist.Invoicing.ManualItem

  defp row(values) do
    Map.merge(
      %{
        "description" => "Netzwerkkabel",
        "quantity" => "3",
        "unit" => "Stk.",
        "unit_price" => "4,5"
      },
      values
    )
  end

  test "a complete row is an item, its amount quantity times price" do
    assert {:ok, item} = ManualItem.parse(row(%{}))

    assert %{kind: "manual", description: "Netzwerkkabel", unit: "Stk.", project_id: nil} = item
    assert Decimal.equal?(item.quantity, Decimal.new(3))
    assert Decimal.equal?(item.unit_price, Decimal.new("4.50"))
    assert Decimal.equal?(item.amount, Decimal.new("13.50"))
    assert item.minutes == nil and item.hours == nil and item.hourly_rate == nil
  end

  test "quantity and price are rounded as stored, and the amount computed from them" do
    assert {:ok, item} =
             ManualItem.parse(row(%{"quantity" => "0,3333", "unit_price" => "10,005"}))

    assert Decimal.equal?(item.quantity, Decimal.new("0.333"))
    assert Decimal.equal?(item.unit_price, Decimal.new("10.01"))
    assert Decimal.equal?(item.amount, Decimal.new("3.33"))

    # A unit is optional, a price of 0 is allowed.
    assert {:ok, %{unit: nil} = free} =
             ManualItem.parse(row(%{"unit" => " ", "unit_price" => "0"}))

    assert Decimal.equal?(free.amount, 0)
    assert {:ok, %{unit_price: zero}} = ManualItem.parse(row(%{"unit_price" => "-0"}))
    refute Decimal.negative?(zero)
  end

  test "numbers can be typed the German way" do
    for {text, number} <- [
          {"2,5", "2.5"},
          {"2.5", "2.5"},
          {"1.250", "1250"},
          {"1.250,75", "1250.75"},
          {"12.500", "12500"},
          {"0.125", "0.125"},
          {"1 250,5", "1250.5"},
          {",5", "0.5"},
          {"85", "85"},
          # Invisible characters, as copying from a web page or PDF brings along.
          {"49,95\u200B", "49.95"},
          {"\uFEFF1.250,00", "1250.00"},
          {"2\u00AD5", "25"}
        ] do
      assert Decimal.equal?(ManualItem.parse_number_text(text), Decimal.new(number)), text
    end

    for text <- ["1,250.50", "1.25,5", "2,5,1", "1e3", "abc", "", "12 €"] do
      assert ManualItem.parse_number_text(text) == nil, text
    end
  end

  test "rows that are not complete say what is missing" do
    assert {:error, errors} =
             ManualItem.parse(%{
               "description" => " ",
               "quantity" => "",
               "unit" => "",
               "unit_price" => ""
             })

    assert errors == %{
             "description" => "enter a description",
             "quantity" => "enter a quantity",
             "unit_price" => "enter a price"
           }

    assert {:error, %{"quantity" => "enter a number above 0 and below 100,000"}} =
             ManualItem.parse(row(%{"quantity" => "0"}))

    assert {:error, %{"quantity" => _}} = ManualItem.parse(row(%{"quantity" => "-1"}))
    assert {:error, %{"quantity" => _}} = ManualItem.parse(row(%{"quantity" => "100.000"}))
    assert {:error, %{"quantity" => _}} = ManualItem.parse(row(%{"quantity" => "drei"}))
    assert {:ok, _} = ManualItem.parse(row(%{"quantity" => "99.999,999"}))

    assert {:error, %{"unit_price" => "enter a price of at least 0 and below 100,000,000"}} =
             ManualItem.parse(row(%{"unit_price" => "-5"}))

    assert {:error, %{"unit_price" => _}} = ManualItem.parse(row(%{"unit_price" => "100000000"}))

    assert {:error, %{"description" => "is too long (at most 500 characters)"}} =
             ManualItem.parse(row(%{"description" => String.duplicate("a", 501)}))
  end

  test "the amount must fit the amount column" do
    assert {:error, %{"amount" => "is too large for one item"}} =
             ManualItem.parse(row(%{"quantity" => "99999", "unit_price" => "99999999"}))

    assert {:ok, _} = ManualItem.parse(row(%{"quantity" => "99", "unit_price" => "99999999"}))
  end

  test "units must fit the unit column and be printable in the invoice font" do
    for unit <- ["Pauschale", "Stunden", "Lizenzen", "m²", "Tag"] do
      assert {:ok, _} = ManualItem.parse(row(%{"unit" => unit})), unit
    end

    assert {:error, %{"unit" => "is too wide for its column, use an abbreviation such as Stk."}} =
             ManualItem.parse(row(%{"unit" => "Quadratmeter"}))

    assert {:error, %{"unit" => message}} = ManualItem.parse(row(%{"unit" => "📦"}))
    assert message =~ "invoice font does not have"
  end

  test "text values are trimmed, line breaks print as spaces" do
    assert {:ok, item} =
             ManualItem.parse(row(%{"description" => "  Kabel\nund Stecker ", "unit" => " kg "}))

    assert item.description == "Kabel und Stecker"
    assert item.unit == "kg"

    assert {:ok, %{quantity: quantity, description: "Kabel"}} =
             ManualItem.parse(row(%{"description" => "Ka\u200Bbel", "quantity" => "\u200E3"}))

    assert Decimal.equal?(quantity, 3)
  end

  test "blank rows and rows sent as a map in their order" do
    assert ManualItem.blank?(%{"description" => " ", "quantity" => "", "id" => "item-1"})
    assert ManualItem.blank?(%{"description" => "\u200B", "unit" => "\u2060 "})
    refute ManualItem.blank?(%{"unit_price" => "5"})
    # Anything but text counts as blank, rather than failing.
    assert ManualItem.blank?(%{"description" => %{"a" => "b"}, "quantity" => ["1"]})

    rows = %{"10" => %{"description" => "c"}, "2" => %{"description" => "b"}, "0" => %{}}

    assert ManualItem.rows(%{"manual_items" => rows}) == [
             %{},
             %{"description" => "b"},
             %{"description" => "c"}
           ]

    assert ManualItem.rows(%{"manual_items" => [%{"description" => "a"}, "x"]}) == [
             %{"description" => "a"}
           ]

    assert ManualItem.rows(%{}) == []
  end

  test "saved items become form rows with German numbers and ids of their own" do
    item = %{
      description: "Kabel",
      quantity: Decimal.new("1250.500"),
      unit: nil,
      unit_price: Decimal.new("4.5")
    }

    row = ManualItem.to_row(item)

    assert %{
             "description" => "Kabel",
             "quantity" => "1250,5",
             "unit" => "",
             "unit_price" => "4,50"
           } =
             row

    assert {:ok, parsed} = ManualItem.parse(row)
    assert Decimal.equal?(parsed.quantity, item.quantity)
    assert ManualItem.to_row(item)["id"] != row["id"]
    assert row["id"] =~ ~r/^item-[0-9a-f]{16}$/
  end
end
