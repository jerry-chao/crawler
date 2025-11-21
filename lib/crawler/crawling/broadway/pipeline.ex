defmodule Crawler.Crawling.Broadway.Pipeline do
  @moduledoc """
  Broadway pipeline for concurrent web crawling operations.

  This module coordinates the crawling process by:
  1. Receiving URL items from the URLProducer
  2. Distributing them to processors for crawling
  3. Handling success and failure cases
  4. Managing backpressure and rate limiting
  """

  use Broadway
  require Logger

  alias Broadway.Message
  alias Crawler.Crawling.Broadway.{URLQueue, URLRegistry, URLProducer}

  @type crawl_result :: :ok | {:error, term()}

  ## Client API

  @doc """
  Starts the Broadway pipeline.
  """
  def start_link(opts \\ []) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {URLProducer, []},
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: get_processor_concurrency(opts),
          min_demand: 1,
          max_demand: get_max_demand(opts)
        ]
      ],
      batchers: [
        # We could add batching for bulk database operations if needed
        # For now, we process each URL individually
      ]
    )
  end

  ## Broadway Callbacks

  @doc """
  Transforms URL items into Broadway messages.
  """
  def transform(url_item, _opts) when is_map(url_item) do
    %Broadway.Message{
      data: url_item,
      acknowledger: Broadway.NoopAcknowledger.init()
    }
  end

  @doc """
  Processes individual crawl messages.
  """
  def handle_message(:default, %Message{data: url_item} = message, _context) do
    Logger.debug("Processing URL: #{url_item.url}")

    case crawl_url(url_item) do
      :ok ->
        URLQueue.mark_processed(url_item.url)
        URLRegistry.mark_crawled(url_item.url)
        Logger.info("Successfully crawled: #{url_item.url}")
        message

      {:error, reason} = error ->
        error_msg = format_error(reason)
        Logger.error("Failed to crawl #{url_item.url}: #{error_msg}")

        URLQueue.mark_failed(url_item.url, should_retry?(reason))
        URLRegistry.mark_failed(url_item.url, error_msg)

        # Mark message as failed but don't crash the processor
        Message.failed(message, error)
    end
  end

  @doc """
  Acknowledges processed messages (no-op with NoopAcknowledger).
  """
  def ack(_ack_ref, _successful, _failed) do
    :ok
  end

  ## Private Functions

  defp crawl_url(%{url: url, module: crawler_module} = _url_item) do
    try do
      # Validate that the crawler module exists and exports crawl/1
      if function_exported?(crawler_module, :crawl, 1) do
        # Execute the crawl
        case crawler_module.crawl(url) do
          :ok -> :ok
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
          other -> {:error, {:unexpected_return, other}}
        end
      else
        {:error, {:invalid_crawler, crawler_module}}
      end
    rescue
      exception ->
        {:error, {:exception, exception}}
    catch
      :exit, reason ->
        {:error, {:exit, reason}}

      :throw, value ->
        {:error, {:throw, value}}
    end
  end

  defp should_retry?({:timeout, _}), do: true
  defp should_retry?({:network_error, _}), do: true
  defp should_retry?({:http_error, status}) when status >= 500, do: true
  defp should_retry?({:browser_error, _}), do: true
  defp should_retry?({:temporary_failure, _}), do: true
  defp should_retry?(_), do: false

  defp format_error({:exception, %{message: message}}), do: "Exception: #{message}"
  defp format_error({:exit, reason}), do: "Process exit: #{inspect(reason)}"
  defp format_error({:throw, value}), do: "Thrown value: #{inspect(value)}"
  defp format_error({:timeout, operation}), do: "Timeout during: #{operation}"
  defp format_error({:network_error, reason}), do: "Network error: #{inspect(reason)}"
  defp format_error({:http_error, status}), do: "HTTP error: #{status}"
  defp format_error({:browser_error, reason}), do: "Browser error: #{inspect(reason)}"
  defp format_error({:invalid_crawler, module}), do: "Invalid crawler module: #{module}"
  defp format_error({:unexpected_return, value}), do: "Unexpected return: #{inspect(value)}"
  defp format_error(reason), do: inspect(reason)

  defp get_processor_concurrency(opts) do
    Keyword.get(opts, :processor_concurrency, get_default_concurrency())
  end

  defp get_max_demand(opts) do
    Keyword.get(opts, :max_demand, 2)
  end

  defp get_default_concurrency do
    # Base concurrency on system capabilities
    # Default to number of schedulers, but cap at reasonable limit
    schedulers = System.schedulers_online()
    min(schedulers * 2, 8)
  end

  ## Public API for monitoring and control

  @doc """
  Gets the current pipeline statistics.
  """
  def get_stats do
    try do
      info =
        Broadway.producer_names(__MODULE__)
        |> Enum.map(&Process.info/1)
        |> Enum.filter(& &1)

      %{
        pipeline_running: length(info) > 0,
        queue_stats: URLQueue.stats(),
        registry_stats: URLRegistry.stats()
      }
    rescue
      _ -> %{pipeline_running: false, error: "Failed to get stats"}
    end
  end

  @doc """
  Checks if the pipeline is healthy and processing URLs.
  """
  def healthy? do
    try do
      stats = get_stats()
      stats.pipeline_running
    rescue
      _ -> false
    end
  end

  @doc """
  Stops the pipeline gracefully.
  """
  def stop do
    Broadway.stop(__MODULE__)
  end

  @doc """
  Adds URLs to the crawling queue.
  """
  def add_urls(url_items) when is_list(url_items) do
    URLQueue.push_batch(url_items)
  end

  def add_url(url_item) when is_map(url_item) do
    URLQueue.push(url_item)
  end

  @doc """
  Gets the current processing status.
  """
  def processing_status do
    %{
      queue_size: URLQueue.size(),
      processing_urls: URLQueue.processing_urls(),
      pipeline_stats: get_stats()
    }
  end
end
