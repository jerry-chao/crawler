defmodule Crawler.Crawling.CrawledPage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Crawler.Crawling.CrawledSite

  @type t :: %__MODULE__{
          id: integer() | nil,
          site_id: integer(),
          url: String.t(),
          title: String.t() | nil,
          content: String.t() | nil,
          content_hash: String.t() | nil,
          metadata: map(),
          status_code: integer() | nil,
          content_type: String.t() | nil,
          content_size: integer() | nil,
          crawled_at: DateTime.t(),
          site: CrawledSite.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "crawled_pages" do
    field :url, :string
    field :title, :string
    field :content, :string
    field :content_hash, :string
    field :metadata, :map, default: %{}
    field :status_code, :integer
    field :content_type, :string
    field :content_size, :integer
    field :crawled_at, :utc_datetime

    belongs_to :site, CrawledSite

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new crawled page.
  """
  def changeset(page, attrs) do
    page
    |> cast(attrs, [
      :site_id,
      :url,
      :title,
      :content,
      :content_hash,
      :metadata,
      :status_code,
      :content_type,
      :content_size,
      :crawled_at
    ])
    |> validate_required([:site_id, :url, :crawled_at])
    |> validate_url(:url)
    |> validate_number(:status_code, greater_than: 0, less_than: 600)
    |> validate_number(:content_size, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:site_id)
    |> unique_constraint(:url)
    |> maybe_generate_content_hash()
  end

  @doc """
  Changeset for updating page content after re-crawling.
  """
  def update_content_changeset(page, attrs) do
    page
    |> cast(attrs, [
      :title,
      :content,
      :content_hash,
      :metadata,
      :status_code,
      :content_type,
      :content_size,
      :crawled_at
    ])
    |> validate_required([:crawled_at])
    |> validate_number(:status_code, greater_than: 0, less_than: 600)
    |> validate_number(:content_size, greater_than_or_equal_to: 0)
    |> maybe_generate_content_hash()
  end

  @doc """
  Generates a hash of the content for change detection.
  """
  def generate_content_hash(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  def generate_content_hash(_), do: nil

  @doc """
  Checks if the page content has changed based on hash comparison.
  """
  def content_changed?(%__MODULE__{content_hash: old_hash}, new_content) do
    new_hash = generate_content_hash(new_content)
    old_hash != new_hash
  end

  @doc """
  Extracts metadata from the page content (title, description, etc.).
  """
  def extract_metadata(content) when is_binary(content) do
    %{
      title: extract_title(content),
      description: extract_description(content),
      keywords: extract_keywords(content),
      content_length: byte_size(content),
      extracted_at: DateTime.utc_now()
    }
  end

  def extract_metadata(_), do: %{}

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

  defp maybe_generate_content_hash(changeset) do
    case get_field(changeset, :content) do
      nil ->
        changeset

      content ->
        put_change(changeset, :content_hash, generate_content_hash(content))
    end
  end

  defp extract_title(content) do
    case Regex.run(~r/<title[^>]*>([^<]+)<\/title>/i, content) do
      [_, title] -> String.trim(title)
      _ -> nil
    end
  end

  defp extract_description(content) do
    case Regex.run(
           ~r/<meta[^>]*name=["\']description["\'][^>]*content=["\']([^"\']+)["\'][^>]*>/i,
           content
         ) do
      [_, description] -> String.trim(description)
      _ -> nil
    end
  end

  defp extract_keywords(content) do
    case Regex.run(
           ~r/<meta[^>]*name=["\']keywords["\'][^>]*content=["\']([^"\']+)["\'][^>]*>/i,
           content
         ) do
      [_, keywords] ->
        keywords
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end
end
