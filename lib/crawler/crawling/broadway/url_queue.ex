defmodule Crawler.Crawling.Broadway.URLQueue do
  @moduledoc """
  A GenServer that manages the queue of URLs to be crawled.

  This module provides a thread-safe queue for storing URLs along with their
  associated crawler modules. It supports adding URLs, retrieving them for
  processing, and tracking processed URLs to avoid duplicates.
  """

  use GenServer
  require Logger

  @type url_item :: %{
          url: String.t(),
          module: module(),
          priority: integer(),
          retries: integer(),
          added_at: DateTime.t()
        }

  @type state :: %{
          queue: :queue.queue(url_item()),
          processing: MapSet.t(String.t()),
          processed: MapSet.t(String.t()),
          stats: %{
            queued: integer(),
            processing: integer(),
            processed: integer(),
            failed: integer()
          }
        }

  ## Client API

  @doc """
  Starts the URLQueue GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds a URL item to the queue.

  ## Examples

      iex> URLQueue.push(%{url: "https://example.com", module: MyApp.Crawlers.Example})
      :ok
  """
  def push(url_item) when is_map(url_item) do
    GenServer.cast(__MODULE__, {:push, normalize_url_item(url_item)})
  end

  @doc """
  Adds multiple URL items to the queue.
  """
  def push_batch(url_items) when is_list(url_items) do
    normalized_items = Enum.map(url_items, &normalize_url_item/1)
    GenServer.cast(__MODULE__, {:push_batch, normalized_items})
  end

  @doc """
  Retrieves the next URL item from the queue for processing.

  Returns `nil` if the queue is empty.
  """
  def pop do
    GenServer.call(__MODULE__, :pop)
  end

  @doc """
  Marks a URL as successfully processed.
  """
  def mark_processed(url) when is_binary(url) do
    GenServer.cast(__MODULE__, {:mark_processed, url})
  end

  @doc """
  Marks a URL as failed and optionally retries it.
  """
  def mark_failed(url, retry? \\ true) when is_binary(url) do
    GenServer.cast(__MODULE__, {:mark_failed, url, retry?})
  end

  @doc """
  Returns the current queue statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Returns the current queue size.
  """
  def size do
    GenServer.call(__MODULE__, :size)
  end

  @doc """
  Checks if a URL is already processed or currently being processed.
  """
  def processed?(url) when is_binary(url) do
    GenServer.call(__MODULE__, {:processed?, url})
  end

  @doc """
  Clears all URLs from the queue and resets statistics.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Returns a list of URLs currently being processed.
  """
  def processing_urls do
    GenServer.call(__MODULE__, :processing_urls)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("URLQueue started")

    state = %{
      queue: :queue.new(),
      processing: MapSet.new(),
      processed: MapSet.new(),
      stats: %{
        queued: 0,
        processing: 0,
        processed: 0,
        failed: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:push, url_item}, state) do
    case should_add_url?(url_item, state) do
      true ->
        new_queue = :queue.in(url_item, state.queue)
        new_stats = update_in(state.stats.queued, &(&1 + 1))

        Logger.debug("Added URL to queue: #{url_item.url}")

        {:noreply, %{state | queue: new_queue, stats: new_stats}}

      false ->
        Logger.debug("Skipping duplicate URL: #{url_item.url}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:push_batch, url_items}, state) do
    {new_queue, added_count} =
      Enum.reduce(url_items, {state.queue, 0}, fn url_item, {queue, count} ->
        if should_add_url?(url_item, state) do
          {:queue.in(url_item, queue), count + 1}
        else
          {queue, count}
        end
      end)

    new_stats = update_in(state.stats.queued, &(&1 + added_count))

    Logger.debug("Added #{added_count} URLs to queue")

    {:noreply, %{state | queue: new_queue, stats: new_stats}}
  end

  @impl true
  def handle_cast({:mark_processed, url}, state) do
    new_processing = MapSet.delete(state.processing, url)
    new_processed = MapSet.put(state.processed, url)

    new_stats = %{
      state.stats
      | processing: state.stats.processing - 1,
        processed: state.stats.processed + 1
    }

    Logger.debug("Marked URL as processed: #{url}")

    {:noreply,
     %{
       state
       | processing: new_processing,
         processed: new_processed,
         stats: new_stats
     }}
  end

  @impl true
  def handle_cast({:mark_failed, url, retry?}, state) do
    new_processing = MapSet.delete(state.processing, url)

    new_stats =
      update_in(state.stats, fn stats ->
        %{stats | processing: stats.processing - 1, failed: stats.failed + 1}
      end)

    state = %{
      state
      | processing: new_processing,
        stats: new_stats
    }

    if retry? do
      # Find the original URL item and increment retries
      case find_and_retry_url(url, state) do
        {:ok, new_state} ->
          Logger.debug("Retrying failed URL: #{url}")
          {:noreply, new_state}

        {:error, _reason} ->
          Logger.warning("Could not retry failed URL: #{url}")
          {:noreply, state}
      end
    else
      Logger.debug("Marked URL as failed (no retry): #{url}")
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:pop, _from, %{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, url_item}, new_queue} ->
        new_processing = MapSet.put(state.processing, url_item.url)

        new_stats = %{
          state.stats
          | queued: state.stats.queued - 1,
            processing: state.stats.processing + 1
        }

        new_state = %{
          state
          | queue: new_queue,
            processing: new_processing,
            stats: new_stats
        }

        Logger.debug("Popped URL from queue: #{url_item.url}")
        {:reply, url_item, new_state}

      {:empty, _queue} ->
        {:reply, nil, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    current_stats = %{
      state.stats
      | queued: :queue.len(state.queue),
        processing: MapSet.size(state.processing)
    }

    {:reply, current_stats, state}
  end

  @impl true
  def handle_call(:size, _from, state) do
    size = :queue.len(state.queue)
    {:reply, size, state}
  end

  @impl true
  def handle_call({:processed?, url}, _from, state) do
    is_processed = MapSet.member?(state.processed, url) or MapSet.member?(state.processing, url)
    {:reply, is_processed, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    new_state = %{
      queue: :queue.new(),
      processing: MapSet.new(),
      processed: MapSet.new(),
      stats: %{
        queued: 0,
        processing: 0,
        processed: 0,
        failed: 0
      }
    }

    Logger.info("URLQueue cleared")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:processing_urls, _from, state) do
    urls = MapSet.to_list(state.processing)
    {:reply, urls, state}
  end

  ## Private Functions

  defp normalize_url_item(%{url: url, module: module} = item) do
    %{
      url: url,
      module: module,
      priority: Map.get(item, :priority, 0),
      retries: Map.get(item, :retries, 0),
      added_at: Map.get(item, :added_at, DateTime.utc_now())
    }
  end

  defp normalize_url_item(%{"url" => url, "module" => module} = item) do
    normalize_url_item(%{
      url: url,
      module: String.to_existing_atom("Elixir.#{module}"),
      priority: Map.get(item, "priority", 0),
      retries: Map.get(item, "retries", 0)
    })
  end

  defp should_add_url?(%{url: url}, state) do
    not (MapSet.member?(state.processed, url) or MapSet.member?(state.processing, url))
  end

  defp find_and_retry_url(url, state) do
    # Create a new URL item for retry with incremented retry count
    url_item = %{
      url: url,
      module: get_crawler_module_for_url(url),
      priority: 0,
      retries: get_retry_count(url) + 1,
      added_at: DateTime.utc_now()
    }

    # Only retry if we haven't exceeded max retries
    max_retries = 3

    if url_item.retries <= max_retries do
      new_queue = :queue.in(url_item, state.queue)
      new_stats = update_in(state.stats.queued, &(&1 + 1))

      {:ok, %{state | queue: new_queue, stats: new_stats}}
    else
      {:error, :max_retries_exceeded}
    end
  end

  defp get_crawler_module_for_url(_url) do
    # For now, return a default crawler module
    # This could be enhanced to determine the appropriate crawler based on URL
    Crawler.Crawlers.Example
  end

  defp get_retry_count(_url) do
    # This could be enhanced to track retry counts per URL
    # For now, return 0
    0
  end
end
