defmodule GranaWeb.Router do
  use GranaWeb, :router

  import GranaWeb.UserAuth

  # CSP aplicada só às rotas do app (não aos dashboards admin/dev, que usam
  # inline scripts/styles). script-src 'self' bloqueia JS injetado (defesa extra
  # de XSS); style-src/img-src/connect-src liberam o necessário p/ charts, logos
  # externos e o websocket do LiveView. frame-src libera só o iframe do
  # widget Pluggy Connect (Open Finance).
  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "script-src 'self' https://connect.pluggy.ai",
                               "style-src 'self' 'unsafe-inline'",
                               "img-src 'self' data: https:",
                               "font-src 'self' data:",
                               "connect-src 'self' ws: wss: https://connect.pluggy.ai https://api.pluggy.ai",
                               "frame-src https://connect.pluggy.ai",
                               "frame-ancestors 'none'",
                               "base-uri 'self'",
                               "form-action 'self'",
                               "object-src 'none'"
                             ],
                             "; "
                           )

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GranaWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "permissions-policy" => "camera=(), microphone=(), geolocation=(), payment=()"
    }

    plug :fetch_current_scope_for_user
  end

  pipeline :setup_complete do
    plug GranaWeb.SetupGate, :complete
  end

  pipeline :setup_pending do
    plug GranaWeb.SetupGate, :pending
  end

  pipeline :csp do
    plug :put_secure_browser_headers, %{"content-security-policy" => @content_security_policy}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  get "/health", GranaWeb.HealthController, :show

  # Webhooks da Pluggy (Open Finance). Fora do pipeline :browser: sem sessão/CSRF;
  # a autenticação é o header secreto conferido no controller.
  scope "/webhooks", GranaWeb do
    pipe_through :api

    post "/pluggy", PluggyWebhookController, :create
  end

  scope "/", GranaWeb do
    pipe_through [:browser, :setup_pending, :csp]

    live_session :setup, on_mount: [{GranaWeb.SetupGate, :setup_pending}] do
      live "/setup", SetupLive, :index
    end
  end

  scope "/", GranaWeb do
    pipe_through [:browser, :csp]

    # A landing é pública mesmo antes do setup (só /setup e o app ficam atrás do portão).
    live_session :public, on_mount: [{GranaWeb.UserAuth, :mount_current_scope}] do
      live "/", LandingLive, :index
    end
  end

  # Diagnóstico (Error tracker e Oban Web): só o dono logado
  use ErrorTracker.Web, :router
  import Oban.Web.Router

  scope "/admin" do
    pipe_through [:browser, :setup_complete, :require_authenticated_user]

    error_tracker_dashboard("/errors",
      on_mount: [
        {GranaWeb.SetupGate, :setup_complete},
        {GranaWeb.UserAuth, :require_authenticated}
      ]
    )

    oban_dashboard("/oban",
      on_mount: [
        {GranaWeb.SetupGate, :setup_complete},
        {GranaWeb.UserAuth, :require_authenticated}
      ]
    )
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
    pipe_through [:browser, :setup_complete, :csp, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {GranaWeb.SetupGate, :setup_complete},
        {GranaWeb.UserAuth, :require_authenticated},
        GranaWeb.PreferencesHook,
        GranaWeb.ImportsHook,
        GranaWeb.AiNoticesHook
      ] do
      live "/onboarding", OnboardingLive, :index
      live "/dashboard", DashboardLive, :index
      live "/upload", UploadLive, :index
      live "/transactions", TransactionsLive, :index
      live "/chat", ChatLive, :index
      live "/chat/new", ChatLive, :new
      live "/chat/:id", ChatLive, :show
      live "/categories", CategoriesLive, :index
      live "/goals", GoalsLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
    get "/transactions/export", TransactionsExportController, :export
    get "/users/settings/backup", BackupController, :download
  end

  scope "/", GranaWeb do
    pipe_through [:browser, :setup_complete, :csp]

    live_session :current_user,
      on_mount: [{GranaWeb.SetupGate, :setup_complete}, {GranaWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/code", UserLive.TwoFactor, :new
      live "/users/reset-password", UserLive.ForgotPassword, :new
      live "/users/reset-password/:token", UserLive.ResetPassword, :edit
    end

    post "/users/log-in", UserSessionController, :create
    post "/users/log-in/code", UserSessionController, :verify_code
    delete "/users/log-out", UserSessionController, :delete
  end
end
