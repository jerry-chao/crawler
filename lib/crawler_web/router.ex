defmodule CrawlerWeb.Router do
  use CrawlerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {CrawlerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CrawlerWeb do
    pipe_through :browser

    get "/", DashboardPage, :page
    get "/dashboard", DashboardPage, :page
  end

  # Other scopes may use custom stacks.
  # scope "/api", CrawlerWeb do
  #   pipe_through :api
  # end

  # Enable development tools in development
  if Application.compile_env(:crawler, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
