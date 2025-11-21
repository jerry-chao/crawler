defmodule Crawler.Repo.Migrations.CreateCrawledPages do
  use Ecto.Migration

  def change do
    create table(:crawled_pages) do
      add :site_id, references(:crawled_sites, on_delete: :delete_all), null: false
      add :url, :string, null: false
      add :title, :string
      add :content, :text
      add :content_hash, :string
      add :metadata, :map, default: %{}
      add :status_code, :integer
      add :content_type, :string
      add :content_size, :integer
      add :crawled_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:crawled_pages, [:url])
    create index(:crawled_pages, [:site_id])
    create index(:crawled_pages, [:crawled_at])
    create index(:crawled_pages, [:content_hash])
    create index(:crawled_pages, [:status_code])
  end
end
