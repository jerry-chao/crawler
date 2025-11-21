defmodule Crawler.Crawling do
  @moduledoc """
  The Crawling context for managing crawled sites, pages, and jobs.
  """

  import Ecto.Query, warn: false
  alias Crawler.Repo

  alias Crawler.Crawling.{CrawledSite, CrawledPage, CrawlJob}

  ## Crawled Sites

  @doc """
  Returns the list of crawled sites.

  ## Examples

      iex> list_sites()
      [%CrawledSite{}, ...]

  """
  def list_sites do
    Repo.all(CrawledSite)
  end

  @doc """
  Returns the list of active crawled sites.
  """
  def list_active_sites do
    CrawledSite
    |> where([s], s.status == "active")
    |> Repo.all()
  end

  @doc """
  Gets a single crawled site.

  Raises `Ecto.NoResultsError` if the Crawled site does not exist.

  ## Examples

      iex> get_site!(123)
      %CrawledSite{}

      iex> get_site!(456)
      ** (Ecto.NoResultsError)

  """
  def get_site!(id), do: Repo.get!(CrawledSite, id)

  @doc """
  Gets a crawled site by base URL.
  """
  def get_site_by_url(base_url) do
    Repo.get_by(CrawledSite, base_url: base_url)
  end

  @doc """
  Creates a crawled site.

  ## Examples

      iex> create_site(%{field: value})
      {:ok, %CrawledSite{}}

      iex> create_site(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_site(attrs \\ %{}) do
    %CrawledSite{}
    |> CrawledSite.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a crawled site.

  ## Examples

      iex> update_site(site, %{field: new_value})
      {:ok, %CrawledSite{}}

      iex> update_site(site, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_site(%CrawledSite{} = site, attrs) do
    site
    |> CrawledSite.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates site statistics after crawling.
  """
  def update_site_stats(%CrawledSite{} = site, attrs) do
    site
    |> CrawledSite.update_stats_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates site configuration.
  """
  def update_site_config(%CrawledSite{} = site, config) do
    site
    |> CrawledSite.config_changeset(%{config: config})
    |> Repo.update()
  end

  @doc """
  Deletes a crawled site.

  ## Examples

      iex> delete_site(site)
      {:ok, %CrawledSite{}}

      iex> delete_site(site)
      {:error, %Ecto.Changeset{}}

  """
  def delete_site(%CrawledSite{} = site) do
    Repo.delete(site)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking crawled site changes.

  ## Examples

      iex> change_site(site)
      %Ecto.Changeset{data: %CrawledSite{}}

  """
  def change_site(%CrawledSite{} = site, attrs \\ %{}) do
    CrawledSite.changeset(site, attrs)
  end

  ## Crawled Pages

  @doc """
  Returns the list of crawled pages for a site.
  """
  def list_pages_for_site(site_id) do
    CrawledPage
    |> where([p], p.site_id == ^site_id)
    |> order_by([p], desc: p.crawled_at)
    |> Repo.all()
  end

  @doc """
  Returns paginated crawled pages for a site.
  """
  def list_pages_for_site_paginated(site_id, page_num \\ 1, per_page \\ 20) do
    offset = (page_num - 1) * per_page

    pages =
      CrawledPage
      |> where([p], p.site_id == ^site_id)
      |> order_by([p], desc: p.crawled_at)
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    total_count =
      CrawledPage
      |> where([p], p.site_id == ^site_id)
      |> Repo.aggregate(:count, :id)

    %{
      pages: pages,
      page_number: page_num,
      per_page: per_page,
      total_count: total_count,
      total_pages: ceil(total_count / per_page)
    }
  end

  @doc """
  Searches crawled pages by content.
  """
  def search_pages(query, opts \\ []) do
    site_id = Keyword.get(opts, :site_id)
    page_num = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    offset = (page_num - 1) * per_page

    base_query =
      CrawledPage
      |> where([p], ilike(p.content, ^"%#{query}%") or ilike(p.title, ^"%#{query}%"))

    base_query =
      if site_id do
        where(base_query, [p], p.site_id == ^site_id)
      else
        base_query
      end

    pages =
      base_query
      |> order_by([p], desc: p.crawled_at)
      |> limit(^per_page)
      |> offset(^offset)
      |> preload(:site)
      |> Repo.all()

    total_count = Repo.aggregate(base_query, :count, :id)

    %{
      pages: pages,
      query: query,
      page_number: page_num,
      per_page: per_page,
      total_count: total_count,
      total_pages: ceil(total_count / per_page)
    }
  end

  @doc """
  Gets a single crawled page.
  """
  def get_page!(id), do: Repo.get!(CrawledPage, id)

  @doc """
  Gets a page by URL.
  """
  def get_page_by_url(url) do
    Repo.get_by(CrawledPage, url: url)
  end

  @doc """
  Creates a crawled page.
  """
  def create_page(attrs \\ %{}) do
    %CrawledPage{}
    |> CrawledPage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates or updates a crawled page.
  """
  def upsert_page(attrs) do
    case get_page_by_url(attrs.url || attrs["url"]) do
      nil ->
        create_page(attrs)

      existing_page ->
        existing_page
        |> CrawledPage.update_content_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Updates a crawled page.
  """
  def update_page(%CrawledPage{} = page, attrs) do
    page
    |> CrawledPage.update_content_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a crawled page.
  """
  def delete_page(%CrawledPage{} = page) do
    Repo.delete(page)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking crawled page changes.
  """
  def change_page(%CrawledPage{} = page, attrs \\ %{}) do
    CrawledPage.changeset(page, attrs)
  end

  ## Crawl Jobs

  @doc """
  Returns the list of crawl jobs.
  """
  def list_jobs do
    CrawlJob
    |> order_by([j], desc: j.inserted_at)
    |> preload(:site)
    |> Repo.all()
  end

  @doc """
  Returns the list of crawl jobs for a site.
  """
  def list_jobs_for_site(site_id) do
    CrawlJob
    |> where([j], j.site_id == ^site_id)
    |> order_by([j], desc: j.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the list of running crawl jobs.
  """
  def list_running_jobs do
    CrawlJob
    |> where([j], j.status == "running")
    |> preload(:site)
    |> Repo.all()
  end

  @doc """
  Gets a single crawl job.
  """
  def get_job!(id), do: Repo.get!(CrawlJob, id) |> Repo.preload(:site)

  @doc """
  Creates a crawl job.
  """
  def create_job(attrs \\ %{}) do
    %CrawlJob{}
    |> CrawlJob.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Starts a crawl job.
  """
  def start_job(%CrawlJob{} = job) do
    job
    |> CrawlJob.start_changeset()
    |> Repo.update()
  end

  @doc """
  Updates job progress.
  """
  def update_job_progress(%CrawlJob{} = job, attrs) do
    job
    |> CrawlJob.progress_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Completes a crawl job.
  """
  def complete_job(%CrawlJob{} = job, status \\ "completed") do
    job
    |> CrawlJob.complete_changeset(status)
    |> Repo.update()
  end

  @doc """
  Adds error information to a job.
  """
  def add_job_error(%CrawlJob{} = job, error_message) do
    job
    |> CrawlJob.error_changeset(error_message)
    |> Repo.update()
  end

  @doc """
  Deletes a crawl job.
  """
  def delete_job(%CrawlJob{} = job) do
    Repo.delete(job)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking crawl job changes.
  """
  def change_job(%CrawlJob{} = job, attrs \\ %{}) do
    CrawlJob.changeset(job, attrs)
  end

  ## Statistics and Analytics

  @doc """
  Returns crawling statistics across all sites.
  """
  def get_crawling_stats do
    sites_count = Repo.aggregate(CrawledSite, :count, :id)
    pages_count = Repo.aggregate(CrawledPage, :count, :id)

    active_sites_count =
      CrawledSite
      |> where([s], s.status == "active")
      |> Repo.aggregate(:count, :id)

    running_jobs_count =
      CrawlJob
      |> where([j], j.status == "running")
      |> Repo.aggregate(:count, :id)

    recent_pages_count =
      CrawledPage
      |> where([p], p.crawled_at >= ago(24, "hour"))
      |> Repo.aggregate(:count, :id)

    %{
      total_sites: sites_count,
      active_sites: active_sites_count,
      total_pages: pages_count,
      running_jobs: running_jobs_count,
      pages_last_24h: recent_pages_count
    }
  end

  @doc """
  Returns statistics for a specific site.
  """
  def get_site_stats(site_id) do
    pages_count =
      CrawledPage
      |> where([p], p.site_id == ^site_id)
      |> Repo.aggregate(:count, :id)

    jobs_count =
      CrawlJob
      |> where([j], j.site_id == ^site_id)
      |> Repo.aggregate(:count, :id)

    last_crawl =
      CrawledPage
      |> where([p], p.site_id == ^site_id)
      |> order_by([p], desc: p.crawled_at)
      |> limit(1)
      |> select([p], p.crawled_at)
      |> Repo.one()

    %{
      pages_count: pages_count,
      jobs_count: jobs_count,
      last_crawl: last_crawl
    }
  end

  @doc """
  Returns recent crawling activity.
  """
  def get_recent_activity(limit \\ 10) do
    recent_pages =
      CrawledPage
      |> order_by([p], desc: p.crawled_at)
      |> limit(^limit)
      |> preload(:site)
      |> Repo.all()

    recent_jobs =
      CrawlJob
      |> order_by([j], desc: j.inserted_at)
      |> limit(^limit)
      |> preload(:site)
      |> Repo.all()

    %{
      recent_pages: recent_pages,
      recent_jobs: recent_jobs
    }
  end
end
