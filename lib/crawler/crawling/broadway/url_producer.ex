defmodule Crawler.Crawling.Broadway.URLProducer do
  @moduledoc """
  A GenStage producer that provides URL items to the Broadway pipeline.

  This module pulls URLs from the URLQueue and provides them to Broadway
  processors for crawling. It implements backpressure to ensure the system
  doesn't get overwhelmed with too many concurrent requests.
  """

  use GenStage
  require Logger

  alias Crawler.Crawling.Broadway.URLQueue

  @type state :: %{
          demand: integer(),
          queue_check_interval: integer(),
          last_queue_check: integer()
        }

  # Default interval to check queue when no URLs are available (in milliseconds)
  @default_queue_check_interval 1000

  ## Client API

  @doc """
  Starts the URLProducer GenStage.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## GenStage Callbacks

  @impl true
  def init(opts) do
    queue_check_interval = Keyword.get(opts, :queue_check_interval, @default_queue_check_interval)

    state = %{
      demand: 0,
      queue_check_interval: queue_check_interval,
      last_queue_check: System.monotonic_time(:millisecond)
    }

    Logger.info("URLProducer started with queue check interval: #{queue_check_interval}ms")

    {:producer, state}
  end

  @impl true
  def handle_demand(incoming_demand, %{demand: pending_demand} = state) do
    total_demand = incoming_demand + pending_demand

    Logger.debug(
      "URLProducer received demand: #{incoming_demand}, total pending: #{total_demand}"
    )

    # Try to fulfill demand immediately
    {events, remaining_demand} = fetch_urls(total_demand)

    new_state = %{state | demand: remaining_demand}

    if remaining_demand > 0 and length(events) == 0 do
      # No URLs available, schedule a check later
      schedule_queue_check(state.queue_check_interval)
    end

    {:noreply, events, new_state}
  end

  @impl true
  def handle_info(:check_queue, state) do
    if state.demand > 0 do
      {events, remaining_demand} = fetch_urls(state.demand)

      new_state = %{
        state
        | demand: remaining_demand,
          last_queue_check: System.monotonic_time(:millisecond)
      }

      if remaining_demand > 0 and length(events) == 0 do
        # Still no URLs, schedule another check
        schedule_queue_check(state.queue_check_interval)
      end

      {:noreply, events, new_state}
    else
      {:noreply, [], state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("URLProducer received unexpected message: #{inspect(msg)}")
    {:noreply, [], state}
  end

  ## Private Functions

  defp fetch_urls(demand) when demand <= 0, do: {[], 0}

  defp fetch_urls(demand) do
    fetch_urls_recursive(demand, [])
  end

  defp fetch_urls_recursive(0, acc), do: {Enum.reverse(acc), 0}

  defp fetch_urls_recursive(remaining_demand, acc) do
    case URLQueue.pop() do
      nil ->
        # No more URLs available
        {Enum.reverse(acc), remaining_demand}

      url_item ->
        Logger.debug("URLProducer fetched URL: #{url_item.url}")
        fetch_urls_recursive(remaining_demand - 1, [url_item | acc])
    end
  end

  defp schedule_queue_check(interval) do
    Process.send_after(self(), :check_queue, interval)
  end
end
