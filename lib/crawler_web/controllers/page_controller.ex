defmodule CrawlerWeb.PageController do
  use CrawlerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
