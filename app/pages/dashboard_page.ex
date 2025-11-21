defmodule CrawlerWeb.DashboardPage do
  use Hologram.Page

  alias Crawler.Crawling
  alias Crawler.Crawling.Broadway.Pipeline

  route "/"
  route "/dashboard"

  def init(_params, _component_state, _server) do
    stats = get_dashboard_stats()

    {:ok,
     %{
       stats: stats,
       sites_count: length(Crawling.list_active_sites())
     }}
  end

  def template do
    """
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Web Crawler Dashboard</h1>
          <p class="mt-2 text-sm text-gray-600">Monitor and manage your web crawling operations</p>
        </div>

    <!-- Stats Grid -->
        <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4 mb-8">
          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <div class="w-8 h-8 bg-blue-500 rounded-full flex items-center justify-center">
                    <span class="text-white text-sm font-bold">S</span>
                  </div>
                </div>
                <div class="ml-5">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Total Sites</dt>
                    <dd class="text-lg font-medium text-gray-900">{@stats.total_sites}</dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <div class="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center">
                    <span class="text-white text-sm font-bold">A</span>
                  </div>
                </div>
                <div class="ml-5">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Active Sites</dt>
                    <dd class="text-lg font-medium text-gray-900">{@stats.active_sites}</dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <div class="w-8 h-8 bg-purple-500 rounded-full flex items-center justify-center">
                    <span class="text-white text-sm font-bold">P</span>
                  </div>
                </div>
                <div class="ml-5">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Total Pages</dt>
                    <dd class="text-lg font-medium text-gray-900">{@stats.total_pages}</dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <div class="w-8 h-8 bg-yellow-500 rounded-full flex items-center justify-center">
                    <span class="text-white text-sm font-bold">J</span>
                  </div>
                </div>
                <div class="ml-5">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Running Jobs</dt>
                    <dd class="text-lg font-medium text-gray-900">{@stats.running_jobs}</dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>
        </div>

    <!-- Actions -->
        <div class="bg-white shadow rounded-lg p-6">
          <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Actions</h3>
          <div class="flex space-x-4">
            <button
              type="button"
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              $click="start_example_crawl"
            >
              Start Example Crawl
            </button>
            <button
              type="button"
              class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              $click="refresh_stats"
            >
              Refresh Stats
            </button>
          </div>
        </div>

    <!-- Basic Info -->
        <div class="mt-8 bg-white shadow rounded-lg p-6">
          <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">System Status</h3>
          <div class="space-y-2">
            <p class="text-sm text-gray-600">
              Active Sites: {String.to_integer(to_string(@sites_count))}
            </p>
            <p class="text-sm text-gray-600">Pages Crawled (24h): {@stats.pages_last_24h}</p>
            <p class="text-sm text-gray-600">
              System Status:
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                Online
              </span>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def action("start_example_crawl", _params, state) do
    # Initialize the example crawler
    case Crawler.Crawlers.Example.init() do
      :ok ->
        # Refresh stats
        new_stats = get_dashboard_stats()
        {:ok, Map.put(state, :stats, new_stats)}

      {:error, _reason} ->
        {:ok, state}
    end
  end

  def action("refresh_stats", _params, state) do
    stats = get_dashboard_stats()
    {:ok, Map.put(state, :stats, stats)}
  end

  defp get_dashboard_stats do
    try do
      Crawling.get_crawling_stats()
    rescue
      _ ->
        %{
          total_sites: 0,
          active_sites: 0,
          total_pages: 0,
          running_jobs: 0,
          pages_last_24h: 0
        }
    end
  end
end
