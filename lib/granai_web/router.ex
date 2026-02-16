defmodule GranaiWeb.Router do
  use GranaiWeb, :router

  import GranaiWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GranaiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GranaiWeb do
    pipe_through :browser

    live_session :public, on_mount: [{GranaiWeb.UserAuth, :mount_current_scope}] do
      live "/", LandingLive, :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:granai, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GranaiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", GranaiWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{GranaiWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive, :index
      live "/upload", UploadLive, :index
      live "/transactions", TransactionsLive, :index
      live "/statements", StatementsLive, :index
      live "/analysis", AnalysisLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", GranaiWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{GranaiWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
