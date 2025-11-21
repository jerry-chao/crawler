defmodule Crawler.Crawlers.Behaviour do
  @moduledoc """
  Behaviour for implementing site-specific crawlers.

  This behaviour defines the interface that all crawlers must implement
  to work with the Broadway pipeline system. Each crawler is responsible
  for crawling a specific site or set of sites with custom logic.
  """

  @type crawl_result :: :ok | {:ok, term()} | {:error, term()}
  @type url :: String.t()
  @type crawler_config :: map()

  @doc """
  Initializes the crawler and adds the initial URLs to the crawling queue.

  This function is called when the crawler is first set up and should
  add the starting URLs for the site to the crawling system.
  """
  @callback init() :: :ok | {:error, term()}

  @doc """
  Crawls a single URL and processes its content.

  This is the main crawling function that will be called by the Broadway
  pipeline for each URL. It should:
  1. Visit the URL using Wallaby or other HTTP client
  2. Extract and process the page content
  3. Find and queue new URLs to crawl
  4. Store the extracted content in the database

  ## Parameters
  - `url`: The URL to crawl

  ## Returns
  - `:ok` on successful crawl
  - `{:ok, result}` on successful crawl with additional data
  - `{:error, reason}` on failure
  """
  @callback crawl(url()) :: crawl_result()

  @doc """
  Extracts links from the current page session.

  This function should use the Wallaby session to find and extract
  links that should be added to the crawling queue.

  ## Parameters
  - `session`: Active Wallaby browser session

  ## Returns
  List of URLs to be crawled
  """
  @callback extract_links(Wallaby.Session.t()) :: [url()]

  @doc """
  Extracts and processes content from the current page.

  This function should extract the relevant content from the page
  and return it in a structured format for storage.

  ## Parameters
  - `session`: Active Wallaby browser session
  - `url`: The current page URL

  ## Returns
  Map containing extracted content and metadata
  """
  @callback extract_content(Wallaby.Session.t(), url()) :: map()

  @doc """
  Validates if a URL should be crawled based on crawler-specific rules.

  This function allows crawlers to implement custom filtering logic
  to determine if a URL should be crawled or skipped.

  ## Parameters
  - `url`: The URL to validate

  ## Returns
  - `true` if the URL should be crawled
  - `false` if the URL should be skipped
  """
  @callback should_crawl_url?(url()) :: boolean()

  @doc """
  Gets the crawler configuration for this crawler instance.

  Returns the default configuration for this crawler, which can be
  overridden when creating crawled sites in the database.
  """
  @callback get_config() :: crawler_config()

  @doc """
  Handles errors that occur during crawling.

  This optional callback allows crawlers to implement custom error
  handling logic, such as logging specific errors or performing
  recovery actions.

  ## Parameters
  - `url`: The URL that failed to crawl
  - `error`: The error that occurred

  ## Returns
  - `:retry` to retry the URL
  - `:skip` to skip the URL
  - `:stop` to stop crawling this site
  """
  @callback handle_error(url(), term()) :: :retry | :skip | :stop

  @optional_callbacks [handle_error: 2]

  @doc """
  Helper macro for implementing crawlers with default implementations.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Crawler.Crawlers.Behaviour

      require Logger
      alias Crawler.Crawling.Broadway.{URLQueue, URLRegistry}
      alias Crawler.Crawling
      alias Wallaby.{Browser, Element, Query, Session}

      @doc """
      Default error handler that logs the error and returns :retry for
      network/timeout errors, :skip for other errors.
      """
      def handle_error(url, error) do
        Logger.error("Crawler error for #{url}: #{inspect(error)}")

        case error do
          {:timeout, _} -> :retry
          {:network_error, _} -> :retry
          {:http_error, status} when status >= 500 -> :retry
          {:browser_error, _} -> :retry
          _ -> :skip
        end
      end

      @doc """
      Default configuration returns an empty map.
      """
      def get_config, do: %{}

      @doc """
      Helper function to start a Wallaby session with appropriate configuration.
      """
      def start_session(opts \\ []) do
        session_opts = Keyword.merge(default_session_opts(), opts)

        case Wallaby.start_session(session_opts) do
          {:ok, session} -> {:ok, session}
          {:error, reason} -> {:error, {:browser_error, reason}}
        end
      end

      @doc """
      Helper function to safely end a Wallaby session.
      """
      def end_session(session) do
        try do
          Wallaby.end_session(session)
        rescue
          error ->
            Logger.warning("Error ending Wallaby session: #{inspect(error)}")
            :ok
        end
      end

      @doc """
      Helper function to store discovered links in the crawling queue.
      """
      def store_links(links, crawler_module \\ __MODULE__) when is_list(links) do
        url_items =
          links
          |> Enum.filter(&should_crawl_url?/1)
          |> Enum.reject(&URLRegistry.registered?/1)
          |> Enum.map(&create_url_item(&1, crawler_module))

        if length(url_items) > 0 do
          URLQueue.push_batch(url_items)
          Logger.debug("Added #{length(url_items)} URLs to crawling queue")
        end

        :ok
      end

      @doc """
      Helper function to store crawled content in the database.
      """
      def store_content(url, content, site_id) when is_map(content) do
        attrs =
          Map.merge(content, %{
            site_id: site_id,
            url: url,
            crawled_at: DateTime.utc_now()
          })

        case Crawling.upsert_page(attrs) do
          {:ok, page} ->
            Logger.debug("Stored content for: #{url}")
            {:ok, page}

          {:error, changeset} ->
            Logger.error("Failed to store content for #{url}: #{inspect(changeset.errors)}")
            {:error, {:storage_error, changeset.errors}}
        end
      end

      @doc """
      Default Wallaby session options for crawlers.
      """
      def default_session_opts do
        [
          capabilities: %{
            chromeOptions: %{
              args: [
                "--headless",
                "--no-sandbox",
                "--disable-gpu",
                "--disable-dev-shm-usage",
                "--window-size=1280,800",
                "--user-agent=#{default_user_agent()}"
              ]
            }
          }
        ]
      end

      @doc """
      Default User-Agent string for polite crawling.
      """
      def default_user_agent do
        "Crawler Bot 1.0 (+http://localhost:4000/robots.txt)"
      end

      @doc """
      Creates a URL item map for the crawling queue.
      """
      def create_url_item(url, crawler_module) do
        %{
          url: url,
          module: crawler_module,
          priority: 0,
          added_at: DateTime.utc_now()
        }
      end

      @doc """
      Helper to safely extract text from an element.
      """
      def safe_text(session_or_element, selector \\ nil) do
        try do
          case selector do
            nil -> Element.text(session_or_element)
            _ -> Browser.find(session_or_element, Query.css(selector)) |> Element.text()
          end
        rescue
          _ -> nil
        end
      end

      @doc """
      Helper to safely extract an attribute from an element.
      """
      def safe_attr(element, attribute) do
        try do
          Element.attr(element, attribute)
        rescue
          _ -> nil
        end
      end

      @doc """
      Helper to resolve relative URLs to absolute URLs.
      """
      def resolve_url(base_url, relative_url) do
        base_uri = URI.parse(base_url)
        relative_uri = URI.parse(relative_url)

        case relative_uri do
          %URI{scheme: nil, host: nil} ->
            # Relative URL
            base_uri
            |> URI.merge(relative_uri)
            |> URI.to_string()

          _ ->
            # Already absolute
            relative_url
        end
      end

      defoverridable handle_error: 2, get_config: 0
    end
  end
end
