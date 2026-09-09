defmodule QuorumWeb.Router do
  use QuorumWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug QuorumWeb.BrowserToken
    plug :fetch_live_flash
    plug :put_root_layout, html: {QuorumWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", QuorumWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/start", RoomController, :create
    get "/demo", DemoController, :student
    get "/demo/host", DemoController, :host
    get "/demo/project", DemoController, :project
    live "/join", JoinLive, :index
    live "/r/:code", AttendeeLive, :show
    live "/host/:host_token", HostLive, :show
    live "/host/:host_token/project", ProjectionLive, :show
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:quorum, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: QuorumWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
