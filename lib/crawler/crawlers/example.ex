defmodule Crawler.Crawlers.Example do
  @moduledoc """
  Example crawler implementation for crawling example.com and related IANA sites.

  This crawler demonstrates how to implement the Crawler.Behaviour for a specific
  site, including link extraction, content processing, and URL filtering.
  """

  use Crawler.Crawlers.Behaviour

  alias Wallaby.{Browser, Element, Query}
  alias Crawler.Crawling

  @base_domains ["example.com", "www.iana.org", "iana.org"]
  @allowed_schemes ["http", "https"]

  ## Behaviour Implementation

  @impl true
  def init do
    Logger.info("Initializing Example crawler")

    # Find or create the site entry
    case get_or_create_site() do
      {:ok, _site} ->
        # Add initial URLs to crawling queue
        initial_urls = [
          %{
            url: "https://example.com",
            module: __MODULE__
          },
          %{
            url: "https://www.iana.org",
            module: __MODULE__
          }
        ]

        store_links(Enum.map(initial_urls, & &1.url))
        Logger.info("Added #{length(initial_urls)} initial URLs to crawling queue")
        :ok

      {:error, reason} ->
        Logger.error("Failed to initialize Example crawler: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def crawl(url) do
    Logger.info("Crawling URL: #{url}")

    with {:ok, session} <- start_session(),
         {:ok, session} <- visit_page(session, url),
         {:ok, content} <- extract_content(session, url),
         {:ok, links} <- extract_links(session),
         :ok <- process_links(links),
         {:ok, site} <- get_site(),
         {:ok, _page} <- store_content(url, content, site.id) do
      end_session(session)
      Logger.info("Successfully crawled: #{url}")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to crawl #{url}: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def extract_links(session) do
    try do
      # Extract links from navigation areas and content
      selectors = [
        "header a",
        "nav a",
        "footer a",
        ".content a",
        "main a"
      ]

      links =
        Enum.flat_map(selectors, fn selector ->
          session
          |> Browser.all(Query.css(selector, minimum: 0))
          |> Enum.map(&safe_attr(&1, "href"))
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
        end)
        |> Enum.uniq()
        |> Enum.map(&resolve_relative_url(session, &1))
        |> Enum.filter(&should_crawl_url?/1)

      {:ok, links}
    rescue
      error ->
        {:error, {:link_extraction_failed, error}}
    end
  end

  @impl true
  def extract_content(session, _url) do
    try do
      # Extract page title
      title = safe_text(session, "title") || safe_text(session, "h1")

      # Extract main content
      content_selectors = ["main", ".content", "body"]

      content =
        Enum.find_value(content_selectors, fn selector ->
          try do
            element = Browser.find(session, Query.css(selector))
            Element.text(element)
          rescue
            _ -> nil
          end
        end) || safe_text(session, "body")

      # Extract metadata
      description = extract_meta_description(session)
      keywords = extract_meta_keywords(session)

      # Get page source for full content storage
      page_source = Browser.page_source(session)

      content_data = %{
        title: title,
        content: content,
        metadata: %{
          description: description,
          keywords: keywords,
          content_length: if(content, do: String.length(content), else: 0),
          has_navigation: has_navigation?(session),
          extracted_at: DateTime.utc_now()
        },
        content_type: "text/html",
        content_size: String.length(page_source || ""),
        # Assume success if we got here
        status_code: 200
      }

      {:ok, content_data}
    rescue
      error ->
        {:error, {:content_extraction_failed, error}}
    end
  end

  @impl true
  def should_crawl_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in @allowed_schemes ->
        # Check if host matches our allowed domains
        host in @base_domains or
          Enum.any?(@base_domains, &String.ends_with?(host || "", &1))

      _ ->
        false
    end
  end

  @impl true
  def get_config do
    %{
      name: "Example Site Crawler",
      base_domains: @base_domains,
      allowed_schemes: @allowed_schemes,
      # 1 second delay between requests
      crawl_delay: 1000,
      max_pages: 1000,
      respect_robots_txt: true,
      user_agent: default_user_agent(),
      selectors: %{
        links: ["header a", "nav a", "footer a", ".content a", "main a"],
        title: ["title", "h1"],
        content: ["main", ".content", "body"],
        navigation: ["nav", "header nav", ".navigation"]
      }
    }
  end

  @impl true
  def handle_error(url, error) do
    case error do
      {:timeout, _} ->
        Logger.warning("Timeout crawling #{url}, will retry")
        :retry

      {:browser_error, reason} ->
        Logger.error("Browser error crawling #{url}: #{inspect(reason)}")
        :retry

      {:http_error, status} when status >= 500 ->
        Logger.warning("Server error #{status} for #{url}, will retry")
        :retry

      {:http_error, 404} ->
        Logger.info("Page not found: #{url}, skipping")
        :skip

      {:http_error, status} when status >= 400 ->
        Logger.warning("Client error #{status} for #{url}, skipping")
        :skip

      _ ->
        Logger.error("Unexpected error crawling #{url}: #{inspect(error)}")
        :skip
    end
  end

  ## Private Helper Functions

  defp visit_page(session, url) do
    try do
      session = Browser.visit(session, url)
      # Wait for page to load
      :timer.sleep(500)
      {:ok, session}
    rescue
      error ->
        {:error, {:page_visit_failed, error}}
    end
  end

  defp process_links(links) do
    filtered_links =
      links
      |> Enum.reject(&URLRegistry.registered?/1)
      # Limit to prevent queue overflow
      |> Enum.take(50)

    if length(filtered_links) > 0 do
      store_links(filtered_links)
      Logger.debug("Processed #{length(filtered_links)} new links")
    end

    :ok
  end

  defp resolve_relative_url(session, url) do
    current_url = Browser.current_url(session)
    resolve_url(current_url, url)
  end

  defp extract_meta_description(session) do
    try do
      session
      |> Browser.find(Query.css("meta[name='description']"))
      |> Element.attr("content")
    rescue
      _ -> nil
    end
  end

  defp extract_meta_keywords(session) do
    try do
      keywords_content =
        session
        |> Browser.find(Query.css("meta[name='keywords']"))
        |> Element.attr("content")

      if keywords_content do
        keywords_content
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      else
        []
      end
    rescue
      _ -> []
    end
  end

  defp has_navigation?(session) do
    try do
      session
      |> Browser.all(Query.css("nav, .navigation, header nav"))
      |> length() > 0
    rescue
      _ -> false
    end
  end

  defp get_or_create_site do
    site_attrs = %{
      name: "Example Sites (IANA)",
      base_url: "https://example.com",
      crawler_module: "Crawler.Crawlers.Example",
      config: get_config(),
      status: "active"
    }

    case Crawling.get_site_by_url(site_attrs.base_url) do
      nil ->
        case Crawling.create_site(site_attrs) do
          {:ok, site} ->
            Logger.info("Created new site entry: #{site.name}")
            {:ok, site}

          {:error, changeset} ->
            Logger.error("Failed to create site: #{inspect(changeset.errors)}")
            {:error, {:site_creation_failed, changeset.errors}}
        end

      site ->
        Logger.info("Using existing site entry: #{site.name}")
        {:ok, site}
    end
  end

  defp get_site do
    case Crawling.get_site_by_url("https://example.com") do
      nil -> {:error, :site_not_found}
      site -> {:ok, site}
    end
  end
end
