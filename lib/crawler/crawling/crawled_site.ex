defmodule Crawler.Crawling.CrawledSite do
  use Ecto.Schema
  import Ecto.Changeset

  alias Crawler.Crawling.{CrawledPage, CrawlJob}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          base_url: String.t(),
          crawler_module: String.t(),
          config: map(),
          status: String.t(),
          last_crawled_at: DateTime.t() | nil,
          pages_count: integer(),
          errors_count: integer(),
          crawled_pages: [CrawledPage.t()] | Ecto.Association.NotLoaded.t(),
          crawl_jobs: [CrawlJob.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_statuses ~w(active inactive paused)

  schema "crawled_sites" do
    field :name, :string
    field :base_url, :string
    field :crawler_module, :string
    field :config, :map, default: %{}
    field :status, :string, default: "active"
    field :last_crawled_at, :utc_datetime
    field :pages_count, :integer, default: 0
    field :errors_count, :integer, default: 0

    has_many :crawled_pages, CrawledPage, foreign_key: :site_id
    has_many :crawl_jobs, CrawlJob, foreign_key: :site_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new crawled site.
  """
  def changeset(site, attrs) do
    site
    |> cast(attrs, [:name, :base_url, :crawler_module, :config, :status])
    |> validate_required([:name, :base_url, :crawler_module])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_url(:base_url)
    |> validate_crawler_module(:crawler_module)
    |> unique_constraint(:base_url)
  end

  @doc """
  Changeset for updating site statistics after crawling.
  """
  def update_stats_changeset(site, attrs) do
    site
    |> cast(attrs, [:last_crawled_at, :pages_count, :errors_count, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc """
  Changeset for updating site configuration.
  """
  def config_changeset(site, attrs) do
    site
    |> cast(attrs, [:config, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      uri = URI.parse(url)

      case {uri.scheme, uri.host} do
        {scheme, host} when scheme in ["http", "https"] and is_binary(host) ->
          []

        _ ->
          [{field, "must be a valid HTTP or HTTPS URL"}]
      end
    end)
  end

  defp validate_crawler_module(changeset, field) do
    validate_change(changeset, field, fn _, module_name ->
      try do
        module = String.to_existing_atom("Elixir.#{module_name}")

        if function_exported?(module, :crawl, 1) do
          []
        else
          [{field, "must be a valid crawler module that exports crawl/1"}]
        end
      rescue
        ArgumentError ->
          [{field, "must be an existing module"}]
      end
    end)
  end
end
