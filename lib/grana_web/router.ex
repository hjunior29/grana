defmodule GranaWeb.Router do
  use GranaWeb, :router

  import GranaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GranaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GranaWeb do
    pipe_through :browser

    live_session :public, on_mount: [{GranaWeb.UserAuth, :mount_current_scope}] do
      live "/", LandingLive, :index
      live "/terms", TermsLive, :index
    end
  end

  # Error tracker (available in all environments, admin-only)
  use ErrorTracker.Web, :router
  import Oban.Web.Router

  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    error_tracker_dashboard("/errors")
    oban_dashboard("/oban")
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:grana, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GranaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", GranaWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{GranaWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive, :index
      live "/upload", UploadLive, :index
      live "/transactions", TransactionsLive, :index
      live "/analysis", AnalysisLive, :index
      live "/categories", CategoriesLive, :index
      live "/goals", GoalsLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
    get "/transactions/export", TransactionsExportController, :export
    get "/transactions/export/investments", TransactionsExportController, :export_investments
  end

  scope "/", GranaWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{GranaWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
