defmodule Crawler.Crawling.Broadway.URLRegistry do
  @moduledoc """
  A GenServer that maintains a registry of crawled URLs to prevent duplicate processing.

  This module provides a thread-safe registry for tracking which URLs have been
  crawled, are currently being crawled, or have failed. It uses MapSet for efficient
  membership checking and supports TTL-based expiration for re-crawling.
  """

  use GenServer
  require Logger

  @type url_status :: :crawled | :processing | :failed
  @type url_entry :: %{
          url: String.t(),
          status: url_status(),
          crawled_at: DateTime.t(),
          expires_at: DateTime.t() | nil,
          attempts: integer(),
          last_error: String.t() | nil
        }

  @type state :: %{
          registry: %{String.t() => url_entry()},
          cleanup_timer: reference() | nil
        }

  # Default TTL for crawled URLs (24 hours in seconds)
  @default_ttl 24 * 60 * 60
  # Cleanup interval (1 hour in milliseconds)
  @cleanup_interval 60 * 60 * 1000

  ## Client API

  @doc """
  Starts the URLRegistry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a URL with the given status.

  ## Examples

      iex> URLRegistry.register(%{url: "https://example.com", module: MyApp.Crawler})
      :ok
  """
  def register(url_item, status \\ :processing) when is_map(url_item) do
    url = get_url_from_item(url_item)
    GenServer.cast(__MODULE__, {:register, url, status, nil})
  end

  @doc """
  Registers a URL as successfully crawled.
  """
  def mark_crawled(url, ttl \\ @default_ttl) when is_binary(url) do
    GenServer.cast(__MODULE__, {:register, url, :crawled, ttl})
  end

  @doc """
  Registers a URL as failed.
  """
  def mark_failed(url, error_message \\ nil) when is_binary(url) do
    GenServer.cast(__MODULE__, {:mark_failed, url, error_message})
  end

  @doc """
  Removes a URL from processing status.
  """
  def unregister_processing(url) when is_binary(url) do
    GenServer.cast(__MODULE__, {:unregister_processing, url})
  end

  @doc """
  Checks if a URL is registered with any status.

  ## Examples

      iex> URLRegistry.registered?(%{url: "https://example.com", module: MyApp.Crawler})
      true
  """
  def registered?(url_item) when is_map(url_item) do
    url = get_url_from_item(url_item)
    GenServer.call(__MODULE__, {:registered?, url})
  end

  @doc """
  Checks if a URL is registered and returns its status.
  """
  def get_status(url) when is_binary(url) do
    GenServer.call(__MODULE__, {:get_status, url})
  end

  @doc """
  Gets detailed information about a registered URL.
  """
  def get_entry(url) when is_binary(url) do
    GenServer.call(__MODULE__, {:get_entry, url})
  end

  @doc """
  Returns statistics about the registry.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Returns the total number of registered URLs.
  """
  def size do
    GenServer.call(__MODULE__, :size)
  end

  @doc """
  Clears all entries from the registry.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Manually triggers cleanup of expired entries.
  """
  def cleanup_expired do
    GenServer.cast(__MODULE__, :cleanup_expired)
  end

  @doc """
  Lists URLs by status with optional limit.
  """
  def list_by_status(status, limit \\ 100) when status in [:crawled, :processing, :failed] do
    GenServer.call(__MODULE__, {:list_by_status, status, limit})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("URLRegistry started")

    # Schedule periodic cleanup
    timer = Process.send_after(self(), :cleanup_expired, @cleanup_interval)

    state = %{
      registry: %{},
      cleanup_timer: timer
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:register, url, status, ttl}, state) do
    expires_at = if ttl, do: DateTime.add(DateTime.utc_now(), ttl, :second), else: nil

    entry = %{
      url: url,
      status: status,
      crawled_at: DateTime.utc_now(),
      expires_at: expires_at,
      attempts: get_attempts(state.registry, url) + 1,
      last_error: nil
    }

    new_registry = Map.put(state.registry, url, entry)

    Logger.debug("Registered URL: #{url} with status: #{status}")

    {:noreply, %{state | registry: new_registry}}
  end

  @impl true
  def handle_cast({:mark_failed, url, error_message}, state) do
    current_entry = Map.get(state.registry, url, %{attempts: 0})

    entry = %{
      url: url,
      status: :failed,
      crawled_at: DateTime.utc_now(),
      expires_at: nil,
      attempts: current_entry.attempts + 1,
      last_error: error_message
    }

    new_registry = Map.put(state.registry, url, entry)

    Logger.debug("Marked URL as failed: #{url}")

    {:noreply, %{state | registry: new_registry}}
  end

  @impl true
  def handle_cast({:unregister_processing, url}, state) do
    case Map.get(state.registry, url) do
      %{status: :processing} = entry ->
        # Only remove if it's currently in processing status
        updated_entry = %{entry | status: :crawled, crawled_at: DateTime.utc_now()}
        new_registry = Map.put(state.registry, url, updated_entry)
        {:noreply, %{state | registry: new_registry}}

      _ ->
        # URL not in processing or doesn't exist
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:cleanup_expired, state) do
    {new_registry, removed_count} = cleanup_expired_entries(state.registry)

    if removed_count > 0 do
      Logger.debug("Cleaned up #{removed_count} expired URLs")
    end

    {:noreply, %{state | registry: new_registry}}
  end

  @impl true
  def handle_call({:registered?, url}, _from, state) do
    is_registered =
      case Map.get(state.registry, url) do
        nil -> false
        %{expires_at: nil} -> true
        %{expires_at: expires_at} -> DateTime.compare(DateTime.utc_now(), expires_at) == :lt
      end

    {:reply, is_registered, state}
  end

  @impl true
  def handle_call({:get_status, url}, _from, state) do
    status =
      case Map.get(state.registry, url) do
        nil ->
          nil

        %{status: status, expires_at: nil} ->
          status

        %{status: status, expires_at: expires_at} ->
          if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
            status
          else
            nil
          end
      end

    {:reply, status, state}
  end

  @impl true
  def handle_call({:get_entry, url}, _from, state) do
    entry = Map.get(state.registry, url)
    {:reply, entry, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = calculate_stats(state.registry)
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:size, _from, state) do
    size = map_size(state.registry)
    {:reply, size, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    Logger.info("URLRegistry cleared")
    {:reply, :ok, %{state | registry: %{}}}
  end

  @impl true
  def handle_call({:list_by_status, status, limit}, _from, state) do
    urls =
      state.registry
      |> Enum.filter(fn {_url, entry} ->
        entry.status == status and not expired?(entry)
      end)
      |> Enum.take(limit)
      |> Enum.map(fn {url, _entry} -> url end)

    {:reply, urls, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    {new_registry, removed_count} = cleanup_expired_entries(state.registry)

    if removed_count > 0 do
      Logger.debug("Cleaned up #{removed_count} expired URLs")
    end

    # Schedule next cleanup
    timer = Process.send_after(self(), :cleanup_expired, @cleanup_interval)

    {:noreply, %{state | registry: new_registry, cleanup_timer: timer}}
  end

  ## Private Functions

  defp get_url_from_item(%{url: url}), do: url
  defp get_url_from_item(%{"url" => url}), do: url
  defp get_url_from_item(url) when is_binary(url), do: url

  defp get_attempts(registry, url) do
    case Map.get(registry, url) do
      nil -> 0
      %{attempts: attempts} -> attempts
    end
  end

  defp expired?(%{expires_at: nil}), do: false

  defp expired?(%{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) != :lt
  end

  defp cleanup_expired_entries(registry) do
    {new_registry, removed_count} =
      Enum.reduce(registry, {%{}, 0}, fn {url, entry}, {acc_registry, count} ->
        if expired?(entry) do
          {acc_registry, count + 1}
        else
          {Map.put(acc_registry, url, entry), count}
        end
      end)

    {new_registry, removed_count}
  end

  defp calculate_stats(registry) do
    {crawled, processing, failed, expired} =
      Enum.reduce(registry, {0, 0, 0, 0}, fn {_url, entry}, {c, p, f, e} ->
        if expired?(entry) do
          {c, p, f, e + 1}
        else
          case entry.status do
            :crawled -> {c + 1, p, f, e}
            :processing -> {c, p + 1, f, e}
            :failed -> {c, p, f + 1, e}
          end
        end
      end)

    %{
      total: map_size(registry),
      crawled: crawled,
      processing: processing,
      failed: failed,
      expired: expired
    }
  end
end
