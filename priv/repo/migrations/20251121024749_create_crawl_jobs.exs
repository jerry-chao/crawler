defmodule Crawler.Repo.Migrations.CreateCrawlJobs do
  use Ecto.Migration

  def change do
    create table(:crawl_jobs) do
      add :site_id, references(:crawled_sites, on_delete: :delete_all), null: false
      add :status, :string, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :pages_crawled, :integer, default: 0
      add :pages_found, :integer, default: 0
      add :errors_count, :integer, default: 0
      add :error_details, :text
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:crawl_jobs, [:site_id])
    create index(:crawl_jobs, [:status])
    create index(:crawl_jobs, [:started_at])
    create index(:crawl_jobs, [:completed_at])
  end
end
