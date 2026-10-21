defmodule PotionZeitgeistWeb.Router do
  use PotionZeitgeistWeb, :router

  import PotionZeitgeistWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PotionZeitgeistWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug :require_authenticated_user
  end

  pipeline :require_admin do
    plug :require_authenticated_user
    plug :require_admin_user
  end

  pipeline :require_setup do
    plug :ensure_admin_exists
  end

  # Setup route — only accessible when no admin exists
  scope "/", PotionZeitgeistWeb do
    pipe_through [:browser]

    get "/setup", SetupController, :new
    post "/setup", SetupController, :create
  end

  # Auth routes — redirect to / if already logged in
  scope "/", PotionZeitgeistWeb do
    pipe_through [:browser, :require_setup]

    get "/login", SessionController, :new
    post "/login", SessionController, :create
  end

  # Authenticated user routes
  scope "/", PotionZeitgeistWeb do
    pipe_through [:browser, :require_setup, :require_auth]

    post "/logout", SessionController, :delete

    live_session :authenticated,
      layout: {PotionZeitgeistWeb.Layouts, :app},
      on_mount: [{PotionZeitgeistWeb.UserAuth, :ensure_authenticated}] do
      live "/", DashboardLive
      live "/entries", TimeEntriesLive
    end
  end

  # Export routes (regular controller — not LiveView)
  scope "/export", PotionZeitgeistWeb do
    pipe_through [:browser, :require_setup, :require_auth]

    get "/my-entries", ExportController, :my_entries
  end

  # Admin-only routes
  scope "/admin", PotionZeitgeistWeb do
    pipe_through [:browser, :require_setup, :require_admin]

    live_session :admin,
      layout: {PotionZeitgeistWeb.Layouts, :app},
      on_mount: [{PotionZeitgeistWeb.UserAuth, :ensure_admin}] do
      live "/users", Admin.UsersLive
      live "/users/:id/entries", Admin.UserEntriesLive
      live "/projects", Admin.ProjectsLive
      live "/invoices", Admin.InvoicesLive
      live "/invoices/new", Admin.InvoiceFormLive, :new
      live "/invoices/:id", Admin.InvoiceLive
      live "/invoices/:id/edit", Admin.InvoiceFormLive, :edit
      live "/invoice-templates", Admin.InvoiceTemplatesLive
      live "/invoice-templates/new", Admin.InvoiceTemplateFormLive, :new
      live "/invoice-templates/:id/edit", Admin.InvoiceTemplateFormLive, :edit
    end

    # Standalone A4 page to print an invoice or save it as PDF
    get "/invoices/:id/print", InvoiceController, :print
  end

  # Admin export routes
  scope "/export", PotionZeitgeistWeb do
    pipe_through [:browser, :require_setup, :require_admin]

    get "/users/:id/entries", ExportController, :user_entries
    get "/all", ExportController, :all_entries
  end

  # Dev tools
  if Application.compile_env(:potion_zeitgeist, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PotionZeitgeistWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
