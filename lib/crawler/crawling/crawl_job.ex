defmodule Crawler.Crawling.CrawlJob do
  use Ecto.Schema
  import Ecto.Changeset

  alias Crawler.Crawling.CrawledSite

  @type t :: %__MODULE__{
          id: integer() | nil,
          site_id: integer(),
          status: String.t(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          pages_crawled: integer(),
          pages_found: integer(),
          errors_count: integer(),
          error_details: String.t() | nil,
          config: map(),
          site: CrawledSite.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_statuses ~w(pending running completed failed cancelled)

  schema "crawl_jobs" do
    field :status, :string, default: "pending"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :pages_crawled, :integer, default: 0
    field :pages_found, :integer, default: 0
    field :errors_count, :integer, default: 0
    field :error_details, :string
    field :config, :map, default: %{}

    belongs_to :site, CrawledSite

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new crawl job.
  """
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:site_id, :config, :status])
    |> validate_required([:site_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:site_id)
  end

  @doc """
  Changeset for starting a crawl job.
  """
  def start_changeset(job) do
    job
    |> change(%{
      status: "running",
      started_at: DateTime.utc_now(),
      completed_at: nil,
      pages_crawled: 0,
      pages_found: 0,
      errors_count: 0,
      error_details: nil
    })
  end

  @doc """
  Changeset for updating job progress.
  """
  def progress_changeset(job, attrs) do
    job
    |> cast(attrs, [:pages_crawled, :pages_found, :errors_count])
    |> validate_number(:pages_crawled, greater_than_or_equal_to: 0)
    |> validate_number(:pages_found, greater_than_or_equal_to: 0)
    |> validate_number(:errors_count, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for completing a crawl job.
  """
  def complete_changeset(job, final_status \\ "completed") do
    job
    |> change(%{
      status: final_status,
      completed_at: DateTime.utc_now()
    })
    |> validate_inclusion(:status, ["completed", "failed", "cancelled"])
  end

  @doc """
  Changeset for adding error details to a job.
  """
  def error_changeset(job, error_message) do
    current_errors = job.errors_count + 1

    error_details =
      case job.error_details do
        nil -> error_message
        existing -> existing <> "\n" <> error_message
      end

    job
    |> change(%{
      errors_count: current_errors,
      error_details: error_details
    })
  end

  @doc """
  Calculates the duration of the crawl job.
  """
  def duration(%__MODULE__{started_at: nil}), do: nil

  def duration(%__MODULE__{started_at: started_at, completed_at: nil}) do
    DateTime.diff(DateTime.utc_now(), started_at, :second)
  end

  def duration(%__MODULE__{started_at: started_at, completed_at: completed_at}) do
    DateTime.diff(completed_at, started_at, :second)
  end

  @doc """
  Calculates the crawl rate (pages per second).
  """
  def crawl_rate(%__MODULE__{} = job) do
    case duration(job) do
      nil -> 0.0
      0 -> 0.0
      duration_seconds -> job.pages_crawled / duration_seconds
    end
  end

  @doc """
  Checks if the job is currently running.
  """
  def running?(%__MODULE__{status: "running"}), do: true
  def running?(%__MODULE__{}), do: false

  @doc """
  Checks if the job is completed (successfully or with errors).
  """
  def completed?(%__MODULE__{status: status}) when status in ["completed", "failed", "cancelled"],
    do: true

  def completed?(%__MODULE__{}), do: false

  @doc """
  Gets a summary of the job status for display.
  """
  def summary(%__MODULE__{} = job) do
    %{
      id: job.id,
      status: job.status,
      pages_crawled: job.pages_crawled,
      pages_found: job.pages_found,
      errors_count: job.errors_count,
      duration_seconds: duration(job),
      crawl_rate: crawl_rate(job),
      started_at: job.started_at,
      completed_at: job.completed_at
    }
  end
end
