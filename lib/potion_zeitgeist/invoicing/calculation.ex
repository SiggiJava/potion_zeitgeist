defmodule PotionZeitgeist.Invoicing.Calculation do
  @moduledoc """
  Turns selected time entries into invoice items and totals.

  Each entry counts with its duration rounded to full minutes, so the time
  sheet rows add up to the item. Entries are grouped by project, each group is
  billed in hours rounded to two decimals, and the amount is computed from
  those rounded hours, so "hours × rate = amount" checks out on paper.
  """

  @no_project_description "Dienstleistungen"

  @doc """
  Key for the item of a project: the project id as a string, or `"none"` for
  entries without a project. Used for rate and description form fields.
  """
  def item_key(nil), do: "none"
  def item_key(project_id), do: to_string(project_id)

  @doc """
  Groups completed entries (with `:project` preloaded) by project.

  Returns one map per project, sorted by project name with "no project" last:
  `%{key, project_id, project_name, minutes, entries}`.
  """
  def group_entries(entries) do
    entries
    |> Enum.filter(& &1.clock_out)
    |> Enum.group_by(& &1.project_id)
    |> Enum.map(fn {project_id, group} ->
      %{
        key: item_key(project_id),
        project_id: project_id,
        project_name: project_name(hd(group)),
        minutes: group |> Enum.map(&entry_minutes/1) |> Enum.sum(),
        entries: Enum.sort_by(group, & &1.clock_in, NaiveDateTime)
      }
    end)
    |> Enum.sort_by(fn group ->
      {is_nil(group.project_id), String.downcase(group.project_name || "")}
    end)
  end

  @doc """
  Builds invoice items for the groups.

  `rate_for` and `description_for` are functions that receive a group and
  return its hourly rate (a `Decimal`, or `nil` when missing) and description
  (blank falls back to the project name).
  """
  def build_items(groups, rate_for, description_for) do
    groups
    |> Enum.with_index(1)
    |> Enum.map(fn {group, position} ->
      rate = rate_for.(group)
      hours = hours(group.minutes)

      %{
        key: group.key,
        position: position,
        project_id: group.project_id,
        description: description(description_for.(group), group),
        minutes: group.minutes,
        hours: hours,
        hourly_rate: rate,
        amount: rate && amount(hours, rate)
      }
    end)
  end

  @doc """
  Net, VAT and gross totals for items, with `vat_rate` in percent.
  Items without an amount (missing rate) count as zero.
  """
  def totals(items, vat_rate) do
    net =
      items
      |> Enum.map(&(&1.amount || Decimal.new(0)))
      |> Enum.reduce(Decimal.new("0.00"), &Decimal.add/2)
      |> Decimal.round(2, :half_up)

    vat =
      net
      |> Decimal.mult(Decimal.new(vat_rate || 0))
      |> Decimal.div(100)
      |> Decimal.round(2, :half_up)

    %{
      minutes: items |> Enum.map(& &1.minutes) |> Enum.sum(),
      hours: items |> Enum.map(& &1.hours) |> Enum.reduce(Decimal.new("0.00"), &Decimal.add/2),
      net: net,
      vat: vat,
      gross: Decimal.add(net, vat)
    }
  end

  @doc "Minutes as hours, rounded to two decimals."
  def hours(minutes) do
    minutes |> Decimal.new() |> Decimal.div(60) |> Decimal.round(2, :half_up)
  end

  def amount(hours, rate) do
    hours |> Decimal.mult(rate) |> Decimal.round(2, :half_up)
  end

  @doc "Duration of a completed entry in minutes, rounded half up."
  def entry_minutes(%{clock_out: nil}), do: 0

  def entry_minutes(entry) do
    seconds = entry.clock_out |> NaiveDateTime.diff(entry.clock_in, :second) |> max(0)
    div(seconds + 30, 60)
  end

  defp description(text, group) do
    case text && String.trim(text) do
      blank when blank in [nil, ""] -> default_description(group)
      text -> text
    end
  end

  @doc "The description an item gets when none is entered."
  def default_description(%{project_name: name}) when is_binary(name), do: name
  def default_description(_group), do: @no_project_description

  defp project_name(%{project: %{name: name}}), do: name
  defp project_name(_entry), do: nil
end
