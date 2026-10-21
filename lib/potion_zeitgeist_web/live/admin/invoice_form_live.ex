defmodule PotionZeitgeistWeb.Admin.InvoiceFormLive do
  @moduledoc """
  Creates and edits invoice drafts: pick a month, select its unbilled time
  entries, enter one hourly rate or one per project, and see the amount.

  The form works on plain params (not a changeset) because the selection,
  rates and descriptions are not fields of the invoice. Errors of the last
  save are shown through `to_form/2`'s `:errors`.
  """
  use PotionZeitgeistWeb, :live_view

  alias PotionZeitgeist.Invoicing
  alias PotionZeitgeist.Invoicing.{Calculation, Format, Invoice}

  on_mount {PotionZeitgeistWeb.UserAuth, :ensure_admin}

  @base_deleted "That invoice was deleted in the meantime."

  @impl true
  def mount(params, _session, socket) do
    today = Invoicing.today()
    socket = assign(socket, today: today, templates: Invoicing.list_templates(), errors: [])

    case socket.assigns.live_action do
      :new -> mount_new(socket, params["from"])
      :edit -> mount_edit(socket, Invoicing.get_invoice!(params["id"]))
    end
  end

  defp mount_new(socket, base_id) do
    today = socket.assigns.today
    base_invoices = Invoicing.base_invoices()

    # A link from an invoice page names its invoice, which may have been
    # deleted since; a reconnect mounts again with the same link.
    from = base_id && Invoicing.get_invoice(base_id)

    base =
      cond do
        from -> from
        # With a single client, start from the last invoice right away.
        length(base_invoices) == 1 -> hd(base_invoices)
        true -> nil
      end

    params = Invoicing.new_invoice_params(today, base)

    {params, selected_ids} =
      case base do
        nil ->
          {params, []}

        # A corrected invoice bills the same month and entries again.
        %Invoice{status: "cancelled"} ->
          {Map.put(params, "month", Invoicing.month_param(base.period_start)),
           Invoicing.entry_ids(base)}

        _ ->
          next_month = base.period_end |> Date.add(1) |> Date.beginning_of_month()
          month = Enum.min([next_month, Date.beginning_of_month(today)], Date)
          {Map.put(params, "month", Invoicing.month_param(month)), :projects}
      end

    socket =
      socket
      |> assign(:page_title, "New invoice")
      |> assign(:invoice, %Invoice{})
      |> assign(:base_invoices, base_invoices)
      |> assign(:params, params)
      |> load_month(Invoicing.parse_month(params["month"]))

    socket =
      case selected_ids do
        :projects -> select_base_projects(socket, base)
        ids -> select(socket, Enum.map(ids, &to_string/1))
      end

    socket = if base_id && !from, do: put_flash(socket, :error, @base_deleted), else: socket

    {:ok, refresh(socket)}
  end

  defp mount_edit(socket, %Invoice{status: "draft"} = invoice) do
    params = Invoicing.edit_invoice_params(invoice)

    {:ok,
     socket
     |> assign(:page_title, "Edit draft invoice")
     |> assign(:invoice, invoice)
     |> assign(:base_invoices, [])
     |> assign(:params, params)
     |> load_month(invoice.period_start)
     |> select(params["entry_ids"])
     |> refresh()}
  end

  defp mount_edit(socket, invoice) do
    {:ok,
     socket
     |> put_flash(:error, "Issued invoices can no longer be edited.")
     |> push_navigate(to: ~p"/admin/invoices/#{invoice}")}
  end

  @impl true
  def handle_event("validate", %{"invoice" => incoming} = event, socket) do
    {:noreply,
     socket |> apply_params(incoming, event["_target"]) |> assign(:errors, []) |> refresh()}
  end

  @impl true
  def handle_event("toggle_group", %{"key" => key}, socket) do
    ids =
      socket.assigns.groups
      |> Enum.find(%{entries: []}, &(&1.key == key))
      |> Map.fetch!(:entries)
      |> Enum.map(&to_string(&1.id))

    selected = socket.assigns.selected

    selected =
      if Enum.all?(ids, &MapSet.member?(selected, &1)),
        do: Enum.reduce(ids, selected, &MapSet.delete(&2, &1)),
        else: Enum.reduce(ids, selected, &MapSet.put(&2, &1))

    {:noreply, socket |> assign(:selected, selected) |> refresh()}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    ids = Enum.map(socket.assigns.entries, &to_string(&1.id))
    {:noreply, socket |> select(ids) |> refresh()}
  end

  @impl true
  def handle_event("select_none", _params, socket) do
    {:noreply, socket |> select([]) |> refresh()}
  end

  @impl true
  def handle_event("save", %{"invoice" => incoming}, socket) do
    socket = apply_params(socket, incoming, nil)
    params = Map.put(socket.assigns.params, "entry_ids", MapSet.to_list(socket.assigns.selected))

    result =
      case socket.assigns.invoice do
        %Invoice{id: nil} -> Invoicing.create_draft(params)
        invoice -> Invoicing.update_draft(invoice, params)
      end

    case result do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> put_flash(:info, "Draft saved. Check the preview, then issue the invoice.")
         |> push_navigate(to: ~p"/admin/invoices/#{invoice}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        # A template deleted in the meantime must not be offered again.
        {:noreply,
         socket
         |> assign(:errors, changeset.errors)
         |> assign(:templates, Invoicing.list_templates())
         |> refresh()}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "This draft was deleted in the meantime.")
         |> push_navigate(to: ~p"/admin/invoices")}

      {:error, :not_draft} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "This invoice was issued in the meantime and can no longer be edited."
         )
         |> push_navigate(to: ~p"/admin/invoices/#{socket.assigns.invoice}")}
    end
  end

  # Takes over the submitted form values. Rate and description fields only
  # exist for the projects of the shown month, so values typed for other
  # months are kept. A new month reloads its entries; picking a base invoice
  # copies its recipient, rates and so on.
  #
  # `target` is the field that changed. After a reconnect LiveView resends the
  # whole form with the first field as target, so the base invoice is only
  # applied when the user picked it, and never over values typed since.
  defp apply_params(socket, incoming, target) do
    old = socket.assigns.params
    incoming = drop_unused(incoming)

    params =
      old
      |> Map.merge(Map.drop(incoming, ["rates", "descriptions", "entry_ids"]))
      |> Map.put("rates", Map.merge(old["rates"] || %{}, drop_unused(incoming["rates"])))
      |> Map.put(
        "descriptions",
        Map.merge(old["descriptions"] || %{}, drop_unused(incoming["descriptions"]))
      )

    month = Invoicing.parse_month(params["month"]) || socket.assigns.month
    base_id = params["base_id"]
    selected = incoming |> Map.get("entry_ids", []) |> List.wrap()

    cond do
      month != socket.assigns.month ->
        socket
        |> assign(:params, Map.put(params, "month", Invoicing.month_param(month)))
        |> load_month(month)
        |> select(selected)

      target == ["invoice", "base_id"] and base_id not in [nil, ""] and
          base_id != old["base_id"] ->
        apply_base(socket, params, Invoicing.get_invoice(base_id))

      true ->
        socket
        |> assign(:params, params)
        |> select(selected)
    end
  end

  # A base invoice deleted in another tab is dropped from the select.
  defp apply_base(socket, params, nil) do
    socket
    |> assign(:params, Map.put(params, "base_id", ""))
    |> assign(:base_invoices, Invoicing.base_invoices())
    |> put_flash(:error, @base_deleted)
  end

  defp apply_base(socket, params, base) do
    socket
    |> assign(:params, Invoicing.apply_base(params, base))
    |> select_base_projects(base)
  end

  # On change, LiveView marks fields the user has not touched yet with
  # "_unused_<name>" keys. Kept in the params, they would hide the errors of
  # those fields after a save.
  defp drop_unused(params) when is_map(params) do
    Map.reject(params, fn {key, _value} -> String.starts_with?(key, "_unused_") end)
  end

  defp drop_unused(_params), do: %{}

  defp load_month(socket, month) do
    entries = Invoicing.billable_entries(month, socket.assigns.invoice)

    socket
    |> assign(:month, month)
    |> assign(:entries, entries)
    |> assign(:groups, Calculation.group_entries(entries))
    |> assign(:show_users, entries |> Enum.map(& &1.user_id) |> Enum.uniq() |> length() > 1)
    |> assign(:running_count, Invoicing.running_entry_count(month))
    |> assign(:month_options, month_options(socket.assigns.today, socket.assigns.invoice, month))
  end

  # Only ids of entries shown for the month count.
  defp select(socket, ids) do
    shown = MapSet.new(socket.assigns.entries, &to_string(&1.id))
    selected = ids |> Enum.map(&to_string/1) |> MapSet.new() |> MapSet.intersection(shown)
    assign(socket, :selected, selected)
  end

  defp select_base_projects(socket, base) do
    keys = base |> Invoicing.item_keys() |> MapSet.new()

    ids =
      for entry <- socket.assigns.entries,
          MapSet.member?(keys, Calculation.item_key(entry.project_id)),
          do: to_string(entry.id)

    select(socket, ids)
  end

  defp refresh(socket) do
    %{entries: entries, selected: selected, params: params, errors: errors} = socket.assigns
    selected_entries = Enum.filter(entries, &MapSet.member?(selected, to_string(&1.id)))
    unselected = Enum.reject(entries, &MapSet.member?(selected, to_string(&1.id)))

    group_stats =
      Map.new(socket.assigns.groups, fn group ->
        chosen = Enum.filter(group.entries, &MapSet.member?(selected, to_string(&1.id)))

        {group.key,
         %{
           selected: length(chosen),
           all?: length(chosen) == length(group.entries),
           minutes: chosen |> Enum.map(&Calculation.entry_minutes/1) |> Enum.sum()
         }}
      end)

    socket
    |> assign(:group_stats, group_stats)
    |> assign(:preview, Invoicing.preview(selected_entries, params))
    |> assign(:unselected_count, length(unselected))
    |> assign(
      :unselected_minutes,
      unselected |> Enum.map(&Calculation.entry_minutes/1) |> Enum.sum()
    )
    |> assign(:form, to_form(params, as: :invoice, errors: errors))
  end

  defp month_options(today, invoice, month) do
    today
    |> Invoicing.month_choices(invoice, month)
    |> Enum.map(fn {month, minutes} ->
      label = Calendar.strftime(month, "%B %Y")

      label =
        if minutes > 0, do: "#{label} · #{Format.duration(minutes)} h unbilled", else: label

      {label, Invoicing.month_param(month)}
    end)
  end

  defp base_options(invoices) do
    [
      {"Nothing, start empty", ""}
      | Enum.map(invoices, fn invoice ->
          recipient =
            invoice.recipient |> String.split(["\r\n", "\n"]) |> List.first("") |> String.trim()

          {"#{recipient} · #{invoice.number || "draft"} · #{Calendar.strftime(invoice.period_start, "%B %Y")}",
           to_string(invoice.id)}
        end)
    ]
  end

  defp template_options(templates), do: Enum.map(templates, &{&1.name, to_string(&1.id)})

  defp group_name(%{project_name: nil}), do: "No project"
  defp group_name(%{project_name: name}), do: name

  defp error_message(errors, field) do
    case Keyword.get(errors, field) do
      nil -> nil
      error -> translate_error(error)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={if @invoice.id, do: ~p"/admin/invoices/#{@invoice}", else: ~p"/admin/invoices"}
          class="text-sm text-base-content/60 hover:underline"
        >
          ← {if @invoice.id, do: "Back to the draft", else: "Invoices"}
        </.link>
        <h1 class="text-2xl font-bold">{@page_title}</h1>
      </div>

      <.form for={@form} id="invoice-form" phx-change="validate" phx-submit="save">
        <input type="hidden" name="invoice[entry_ids][]" value="" />

        <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <div class="space-y-6 min-w-0">
            <section class="card bg-base-100 shadow">
              <div class="card-body gap-3">
                <h2 class="card-title text-base">1. Time entries</h2>

                <div class="grid gap-x-4 sm:grid-cols-2">
                  <.input
                    field={@form[:month]}
                    id="invoice-month"
                    type="select"
                    label="Month"
                    options={@month_options}
                  />
                  <.input
                    :if={@base_invoices != []}
                    field={@form[:base_id]}
                    id="invoice-base"
                    type="select"
                    label="Start from invoice"
                    options={base_options(@base_invoices)}
                  />
                </div>
                <p class="text-xs text-base-content/50 -mt-2">
                  Entries count for the month of their clock-in date (UTC), as in the export.
                </p>

                <div
                  :if={@running_count > 0}
                  id="running-warning"
                  role="alert"
                  class="alert alert-warning py-2"
                >
                  <.icon name="hero-clock" class="size-5" />
                  <span class="text-sm">
                    {@running_count} running {if @running_count == 1,
                      do: "entry is",
                      else: "entries are"} in this month. Clock out first to bill them.
                  </span>
                </div>

                <p
                  :if={error_message(@errors, :entries)}
                  id="entries-error"
                  class="text-sm text-error"
                >
                  <.icon name="hero-exclamation-circle" class="size-4" />
                  {error_message(@errors, :entries)}
                </p>

                <%= if @groups == [] do %>
                  <div id="no-entries" class="text-center py-10 text-base-content/60">
                    <.icon name="hero-inbox" class="size-10 text-base-content/30" />
                    <p class="mt-2">No unbilled time in {Calendar.strftime(@month, "%B %Y")}.</p>
                  </div>
                <% else %>
                  <div class="flex gap-2 justify-end">
                    <button
                      type="button"
                      id="select-all"
                      phx-click="select_all"
                      class="btn btn-ghost btn-xs"
                    >
                      Select all
                    </button>
                    <button
                      type="button"
                      id="select-none"
                      phx-click="select_none"
                      class="btn btn-ghost btn-xs"
                    >
                      Select none
                    </button>
                  </div>

                  <div
                    :for={group <- @groups}
                    id={"group-#{group.key}"}
                    class="rounded-box border border-base-300"
                  >
                    <div class="flex items-center justify-between gap-3 px-3 py-2 bg-base-200 rounded-t-box">
                      <div class="min-w-0">
                        <span class="font-semibold">{group_name(group)}</span>
                        <span class="text-sm text-base-content/60">
                          · {@group_stats[group.key].selected} of {length(group.entries)} selected
                          · {Format.duration(@group_stats[group.key].minutes)} h
                        </span>
                      </div>
                      <button
                        type="button"
                        id={"toggle-group-#{group.key}"}
                        phx-click="toggle_group"
                        phx-value-key={group.key}
                        class="btn btn-ghost btn-xs"
                      >
                        {if @group_stats[group.key].all?,
                          do: "Deselect project",
                          else: "Select project"}
                      </button>
                    </div>
                    <table class="table table-sm table-fixed w-full">
                      <tbody>
                        <tr :for={entry <- group.entries} id={"entry-row-#{entry.id}"}>
                          <td class="w-10">
                            <input
                              type="checkbox"
                              id={"entry-#{entry.id}"}
                              name="invoice[entry_ids][]"
                              value={entry.id}
                              checked={MapSet.member?(@selected, to_string(entry.id))}
                              class="checkbox checkbox-sm"
                            />
                          </td>
                          <td class="w-24 whitespace-nowrap">
                            <label for={"entry-#{entry.id}"}>
                              {entry.clock_in |> NaiveDateTime.to_date() |> Date.to_string()}
                            </label>
                          </td>
                          <td :if={@show_users} class="hidden sm:table-cell w-32 truncate text-sm">
                            {entry.user && entry.user.name}
                          </td>
                          <td class="w-20 font-mono text-sm whitespace-nowrap">
                            {entry |> Calculation.entry_minutes() |> Format.duration()} h
                          </td>
                          <td class="text-sm text-base-content/70 truncate" title={entry.notes}>
                            <%!-- On phones the user column is hidden, so the name leads the notes. --%>
                            <span :if={@show_users} class="sm:hidden font-medium text-base-content">
                              {entry.user && entry.user.name} ·
                            </span>
                            {entry.notes || ""}
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                <% end %>
              </div>
            </section>

            <section class="card bg-base-100 shadow">
              <div class="card-body gap-3">
                <h2 class="card-title text-base">2. Hourly rate</h2>
                <div class="flex flex-wrap gap-6">
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      id="rate-mode-single"
                      name="invoice[rate_mode]"
                      value="single"
                      checked={@params["rate_mode"] != "per_project"}
                      class="radio radio-sm"
                    /> One rate for all
                  </label>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      id="rate-mode-per-project"
                      name="invoice[rate_mode]"
                      value="per_project"
                      checked={@params["rate_mode"] == "per_project"}
                      class="radio radio-sm"
                    /> Rate per project
                  </label>
                </div>

                <div :if={@params["rate_mode"] != "per_project"} class="max-w-xs">
                  <.input
                    field={@form[:hourly_rate]}
                    id="hourly-rate"
                    type="text"
                    inputmode="decimal"
                    label="Hourly rate (€)"
                    placeholder="e.g. 85"
                    phx-debounce="300"
                  />
                </div>

                <p :if={error_message(@errors, :rates)} id="rates-error" class="text-sm text-error">
                  <.icon name="hero-exclamation-circle" class="size-4" />
                  {error_message(@errors, :rates)}
                </p>

                <div :if={@groups != []} class="space-y-2">
                  <p class="text-sm text-base-content/60">
                    Text of each item on the invoice{if @params["rate_mode"] == "per_project",
                      do: " and its hourly rate"}:
                  </p>
                  <div
                    :for={group <- @groups}
                    class={[
                      "grid gap-2 items-end",
                      @params["rate_mode"] == "per_project" && "sm:grid-cols-[1fr_9rem]",
                      @group_stats[group.key].selected == 0 && "opacity-50"
                    ]}
                  >
                    <.input
                      id={"description-#{group.key}"}
                      name={"invoice[descriptions][#{group.key}]"}
                      value={@params["descriptions"][group.key]}
                      label={group_name(group)}
                      placeholder={Calculation.default_description(group)}
                      phx-debounce="300"
                    />
                    <.input
                      :if={@params["rate_mode"] == "per_project"}
                      id={"rate-#{group.key}"}
                      name={"invoice[rates][#{group.key}]"}
                      value={@params["rates"][group.key]}
                      label="Rate (€)"
                      inputmode="decimal"
                      placeholder="e.g. 85"
                      phx-debounce="300"
                      class={[
                        "w-full input",
                        @group_stats[group.key].selected > 0 &&
                          is_nil(Invoicing.parse_decimal(@params["rates"][group.key])) &&
                          "input-warning"
                      ]}
                    />
                  </div>
                </div>
              </div>
            </section>

            <section class="card bg-base-100 shadow">
              <div class="card-body gap-3">
                <h2 class="card-title text-base">3. Invoice</h2>
                <.input
                  field={@form[:template_id]}
                  id="invoice-template"
                  type="select"
                  label="Letter template"
                  options={template_options(@templates)}
                  prompt={if @templates == [], do: "No template yet"}
                />
                <.input
                  field={@form[:recipient]}
                  id="invoice-recipient"
                  type="textarea"
                  label="Recipient (name and full address)"
                  rows="4"
                  phx-debounce="300"
                />
                <div class="grid gap-x-4 sm:grid-cols-2">
                  <.input
                    field={@form[:invoice_date]}
                    id="invoice-date"
                    type="date"
                    label="Invoice date"
                  />
                  <.input field={@form[:due_date]} id="invoice-due-date" type="date" label="Due date" />
                </div>
                <p class="text-xs text-base-content/50 -mt-2">
                  When you issue the invoice you can set its date again.
                </p>

                <div class="flex flex-wrap gap-6 mt-2">
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      id="tax-mode-small-business"
                      name="invoice[tax_mode]"
                      value="small_business"
                      checked={@params["tax_mode"] != "standard"}
                      class="radio radio-sm"
                    /> No VAT (small business, § 19 UStG)
                  </label>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      id="tax-mode-standard"
                      name="invoice[tax_mode]"
                      value="standard"
                      checked={@params["tax_mode"] == "standard"}
                      class="radio radio-sm"
                    /> With VAT
                  </label>
                </div>
                <div :if={@params["tax_mode"] == "standard"} class="max-w-xs">
                  <.input
                    field={@form[:vat_rate]}
                    id="vat-rate"
                    type="text"
                    inputmode="decimal"
                    label="VAT rate (%)"
                    phx-debounce="300"
                  />
                </div>

                <.input
                  field={@form[:show_timesheet]}
                  id="show-timesheet"
                  type="checkbox"
                  label="Attach a time sheet"
                />
                <p class="text-xs text-base-content/60 -mt-1">
                  A second page with one row per day and item, including the notes.
                </p>
              </div>
            </section>
          </div>

          <aside class="lg:sticky lg:top-6 self-start">
            <div id="invoice-summary" class="card bg-base-100 shadow">
              <div class="card-body gap-3">
                <h2 class="card-title text-base">Summary</h2>

                <p :if={@preview.items == []} class="text-sm text-base-content/60">
                  Select time entries to bill.
                </p>

                <ul class="space-y-2">
                  <li :for={item <- @preview.items} class="text-sm">
                    <div class="font-medium">{item.description}</div>
                    <div class="flex justify-between gap-2 text-base-content/70">
                      <span class="font-mono">
                        {Format.hours(item.hours)} h × {if item.hourly_rate,
                          do: Format.money(item.hourly_rate),
                          else: "?"}
                      </span>
                      <span class="font-mono">
                        {if item.amount, do: Format.money(item.amount), else: "rate missing"}
                      </span>
                    </div>
                  </li>
                </ul>

                <div class="border-t border-base-300 pt-2 space-y-1 text-sm">
                  <%= if @preview.tax_mode == "standard" do %>
                    <div class="flex justify-between">
                      <span>Net</span>
                      <span class="font-mono">{Format.money(@preview.totals.net)}</span>
                    </div>
                    <div class="flex justify-between">
                      <span>VAT {Format.percent(@preview.vat_rate)}</span>
                      <span class="font-mono">{Format.money(@preview.totals.vat)}</span>
                    </div>
                  <% end %>
                  <div class="flex justify-between font-bold text-base">
                    <span>Total</span>
                    <span id="summary-total" class="font-mono">
                      {Format.money(@preview.totals.gross)}
                    </span>
                  </div>
                  <div class="text-xs text-base-content/60">
                    {Format.hours(@preview.totals.hours)} hours billed
                  </div>
                </div>

                <p :if={@unselected_count > 0} id="unselected-hint" class="text-xs text-warning">
                  Not selected in this month: {@unselected_count} {if @unselected_count == 1,
                    do: "entry",
                    else: "entries"}, {Format.duration(@unselected_minutes)} h.
                </p>

                <p :if={@errors != []} class="text-sm text-error">
                  Please check the highlighted fields.
                </p>

                <button
                  type="submit"
                  id="save-draft"
                  class="btn btn-primary w-full"
                  phx-disable-with="Saving..."
                >
                  Save draft
                </button>
                <p class="text-xs text-base-content/50">
                  You can check the letter before issuing the invoice.
                </p>
              </div>
            </div>
          </aside>
        </div>
      </.form>
    </div>
    """
  end
end
