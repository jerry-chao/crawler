defmodule Crawler.Repo.Migrations.CreateCrawledSites do
  use Ecto.Migration

  def change do
    create table(:crawled_sites) do
      add :name, :string, null: false
      add :base_url, :string, null: false
      add :crawler_module, :string, null: false
      add :config, :map, default: %{}
      add :status, :string, default: "active"
      add :last_crawled_at, :utc_datetime
      add :pages_count, :integer, default: 0
      add :errors_count, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:crawled_sites, [:base_url])
    create index(:crawled_sites, [:status])
    create index(:crawled_sites, [:last_crawled_at])
  end
end
