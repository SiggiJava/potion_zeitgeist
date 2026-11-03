defmodule PotionZeitgeist.Invoicing.ManualItem do
  @moduledoc """
  Items of an invoice that are not billed from time entries, such as
  material or a flat fee: a description, a quantity with an optional unit
  (such as "Stk." or "Pauschale") and a price per unit. The amount is the
  quantity times the price, rounded to cents.

  The invoice form sends each item as a row of strings, `parse/1` turns a
  row into an item or says what is wrong with it. Rows with nothing typed
  in are no items and are left out (see `blank?/1`).

  The limits keep every value inside its column of the printed table (see
  invoice.css): quantities below 100,000 with up to three decimals, prices
  below 100,000,000 with two, amounts that fit the amount column, and units
  as wide as the unit column (measured by
  `PotionZeitgeist.Invoicing.LetterLayout`).
  """

  alias PotionZeitgeist.Invoicing
  alias PotionZeitgeist.Invoicing.{Calculation, LetterLayout}

  @fields ~w(description quantity unit unit_price)

  @max_description 500
  @max_quantity Decimal.new(100_000)
  @max_price Decimal.new(100_000_000)
  # Amounts below this fit the numeric(12,2) amount column and the amount
  # column of the printed table.
  @max_amount Decimal.new(10_000_000_000)

  @doc "The fields of a row, as the form names them."
  def fields, do: @fields

  @doc "Units the form suggests."
  def unit_suggestions, do: ~w(Stk. Std. Tag Pauschale kg m m² Monat Lizenz)

  @doc """
  A row for the form, with an id that tells it apart from the other rows.
  The ids are random, so they do not repeat the ids of rows a browser sends
  back after a server restart (see the form's `"recover"` event).
  """
  def new_row(values \\ %{}) do
    @fields
    |> Map.new(&{&1, ""})
    |> Map.merge(Map.take(values, @fields))
    |> Map.put("id", "item-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower))
  end

  @doc "The form row of a saved manual item, with numbers as Germans type them."
  def to_row(item) do
    new_row(%{
      "description" => item.description,
      "quantity" => number_param(item.quantity),
      "unit" => item.unit || "",
      "unit_price" => item.unit_price |> Decimal.round(2) |> german()
    })
  end

  defp number_param(decimal), do: decimal |> Decimal.normalize() |> german()

  defp german(decimal), do: decimal |> Decimal.to_string(:normal) |> String.replace(".", ",")

  @doc """
  The rows of the form params `"manual_items"`, in order: a list of rows, or
  a map of rows keyed by their index, as a browser sends a form.
  """
  def rows(%{"manual_items" => rows}) when is_list(rows), do: Enum.filter(rows, &is_map/1)

  def rows(%{"manual_items" => %{} = rows}) do
    rows
    |> Enum.sort_by(fn {key, _row} -> index_key(key) end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.filter(&is_map/1)
  end

  def rows(_params), do: []

  defp index_key(key) do
    case Integer.parse(to_string(key)) do
      {index, ""} -> {0, index, ""}
      _ -> {1, 0, to_string(key)}
    end
  end

  @doc "Whether nothing is typed into any field of `row`."
  def blank?(row), do: Enum.all?(@fields, &(value(row, &1) == ""))

  @doc """
  `{:ok, item}` for a complete row, or `{:error, errors}` with a message for
  each field that is missing or wrong, keyed by field name (`"amount"` when
  quantity times price is too large).

  Quantities are rounded to three decimals and prices to two, as stored, and
  the amount is computed from those, so it checks out on paper.
  """
  def parse(row) do
    description = value(row, "description")
    unit = value(row, "unit")
    quantity = row |> value("quantity") |> parse_number(3)
    unit_price = row |> value("unit_price") |> parse_number(2)

    errors =
      %{
        "description" => description_error(description),
        "quantity" => quantity_error(value(row, "quantity"), quantity),
        "unit" => unit_error(unit),
        "unit_price" => price_error(value(row, "unit_price"), unit_price)
      }
      |> Map.reject(fn {_field, error} -> is_nil(error) end)

    if errors == %{} do
      amount = Calculation.amount(quantity, unit_price)

      if Decimal.lt?(amount, @max_amount) do
        {:ok,
         %{
           kind: "manual",
           description: description,
           quantity: quantity,
           unit: if(unit == "", do: nil, else: unit),
           unit_price: unit_price,
           amount: amount,
           project_id: nil,
           minutes: nil,
           hours: nil,
           hourly_rate: nil
         }}
      else
        {:error, %{"amount" => "is too large for one item"}}
      end
    else
      {:error, errors}
    end
  end

  # Values as typed, trimmed, without invisible characters (which a pasted
  # number can hold, see `PotionZeitgeist.Invoicing.LetterLayout.clean/1`).
  # Line breaks (which a text field cannot hold, but a request can) print as
  # spaces in the table. Anything but text and numbers counts as blank.
  defp value(row, field) do
    case Map.get(row, field) do
      value when is_binary(value) ->
        value |> LetterLayout.clean() |> String.replace(~r/\s+/u, " ") |> String.trim()

      value when is_number(value) ->
        to_string(value)

      _other ->
        ""
    end
  end

  @doc """
  Parses a number typed the German way ("1.250,5", "2,5", "1250") or with a
  decimal point ("2.5"). Dots before groups of three digits, as in "1.000"
  or "12.500", separate thousands; "0.125" and "2.50" have a decimal point.
  """
  def parse_number_text(text) when is_binary(text) do
    # Spaces, also non-breaking ones, and invisible characters such as
    # U+200B, which copying a number from a web page or PDF can bring along.
    text = String.replace(text, ~r/[\s\x{00A0}\x{202F}\p{Cf}]/u, "")

    text =
      cond do
        Regex.match?(~r/^[+-]?(\d{1,3}(\.\d{3})+|\d*),\d+$/, text) ->
          text |> String.replace(".", "") |> String.replace(",", ".")

        Regex.match?(~r/^[+-]?[1-9]\d{0,2}(\.\d{3})+$/, text) ->
          String.replace(text, ".", "")

        true ->
          text
      end

    Invoicing.parse_decimal(text)
  end

  def parse_number_text(_text), do: nil

  defp parse_number(text, places) do
    case parse_number_text(text) do
      nil ->
        nil

      number ->
        number = Decimal.round(number, places, :half_up)
        # "-0" is zero.
        if Decimal.eq?(number, 0), do: Decimal.round(Decimal.new(0), places), else: number
    end
  end

  defp description_error(""), do: "enter a description"

  defp description_error(description) do
    if String.length(description) > @max_description,
      do: "is too long (at most #{@max_description} characters)"
  end

  defp quantity_error("", _quantity), do: "enter a quantity"

  defp quantity_error(_text, quantity) do
    unless quantity && Decimal.gt?(quantity, 0) && Decimal.lt?(quantity, @max_quantity),
      do: "enter a number above 0 and below 100,000"
  end

  defp price_error("", _price), do: "enter a price"

  defp price_error(_text, price) do
    unless price && not Decimal.negative?(price) && Decimal.lt?(price, @max_price),
      do: "enter a price of at least 0 and below 100,000,000"
  end

  defp unit_error(""), do: nil

  defp unit_error(unit) do
    case LetterLayout.check_characters(unit) do
      {:error, message} ->
        message

      :ok ->
        if LetterLayout.printed_lines(unit, :unit) > 1,
          do: "is too wide for its column, use an abbreviation such as Stk."
    end
  end
end
