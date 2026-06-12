defmodule GuardaWeb.Router do
  use GuardaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GuardaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug GuardaWeb.RateLimitPlug, limit: 60, window_ms: 60_000
    plug GuardaWeb.AuthPlug
  end

  pipeline :api_public do
    plug :accepts, ["json"]
  end

  scope "/", GuardaWeb do
    pipe_through :browser

    live_session :dashboard, on_mount: [] do
      live "/", DashboardLive, :index
    end
  end

  # Public endpoints (no authentication required)
  scope "/api", GuardaWeb do
    pipe_through :api_public

    get "/health", HealthController, :index
  end

  # Authenticated API endpoints
  scope "/api", GuardaWeb do
    pipe_through :api

    # Core query execution
    post "/query", QueryController, :execute

    # Streaming results (NDJSON)
    post "/query/stream", StreamController, :stream

    # Natural language to SQL
    post "/query/natural", NLQueryController, :translate

    # Federated cross-provider JOIN
    post "/query/federated", FederatedController, :join

    # Async query with webhook callback
    post "/query/async", AsyncQueryController, :submit
    get "/query/:id/status", AsyncQueryController, :status

    # Schema introspection
    post "/schema", SchemaController, :introspect

    # Audit log
    get "/audit", AuditController, :index
    get "/audit/stats", AuditController, :stats
  end

  if Application.compile_env(:guarda, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GuardaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
