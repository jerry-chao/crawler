# Design Document: Hologram Migration and Web Crawling System

## Context

The current Phoenix application uses LiveView for interactive web components. We need to migrate to Hologram framework for better isomorphic rendering and implement a robust web crawling system using Broadway and Wallaby. This involves replacing the entire frontend framework while adding significant new backend functionality.

### Stakeholders
- Development team maintaining the crawler application
- Users who will interact with the new Hologram-based interface
- System administrators managing deployment and monitoring

### Constraints
- Must maintain existing Phoenix backend capabilities
- Chrome/ChromeDriver requirement for Wallaby browser automation
- Need to handle concurrent crawling without overwhelming target sites
- Database storage for potentially large amounts of crawled content

## Goals / Non-Goals

### Goals
- Complete migration from LiveView to Hologram with feature parity
- Implement production-ready web crawling system with Broadway
- Create intuitive interface for managing and viewing crawled content
- Ensure crawling system respects robots.txt and rate limiting
- Maintain application performance during framework migration

### Non-Goals
- Supporting both LiveView and Hologram simultaneously
- Building a general-purpose search engine crawler
- Real-time streaming of crawl results (batch updates acceptable)
- Advanced content analysis or NLP processing

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Phoenix Application                       │
├─────────────────────┬───────────────────────────────────────┤
│   Hologram Web      │           Crawling System             │
│                     │                                       │
│  ┌─────────────┐    │  ┌──────────────┐                    │
│  │ Pages       │    │  │   Broadway   │                    │
│  │ Components  │◄───┼──┤   Pipeline   │                    │
│  │ Layouts     │    │  └──────┬───────┘                    │
│  └─────────────┘    │         │                            │
│                     │  ┌──────▼───────┐   ┌──────────────┐ │
│                     │  │ URLProducer  │◄──┤  URLQueue    │ │
│                     │  └──────────────┘   │  (GenServer) │ │
│                     │                     └──────────────┘ │
│                     │  ┌──────────────┐   ┌──────────────┐ │
│                     │  │   Crawlers   │───┤ URLRegistry  │ │
│                     │  │   (Wallaby)  │   │ (GenServer)  │ │
│                     │  └──────────────┘   └──────────────┘ │
└─────────────────────┴───────────────────────────────────────┘
                              │
                      ┌───────▼────────┐
                      │   PostgreSQL   │
                      │   Database     │
                      └────────────────┘
```

## Technical Decisions

### 1. Framework Migration Strategy
**Decision**: Complete replacement rather than gradual migration
**Rationale**: LiveView and Hologram have different architectural patterns and mixing them would create complexity
**Alternatives Considered**: 
- Gradual page-by-page migration: Rejected due to routing and state management conflicts
- Keeping LiveView for admin pages: Rejected to maintain consistency

### 2. Crawling Architecture - Broadway + Wallaby
**Decision**: Use Broadway for concurrency management with Wallaby for browser automation
**Rationale**: Broadway provides built-in backpressure and batching, Wallaby handles JavaScript-heavy sites
**Alternatives Considered**:
- Simple GenServer pool: Rejected due to lack of backpressure handling
- HTTPoison/Req only: Rejected because many modern sites require JavaScript execution

### 3. URL Management Strategy
**Decision**: Separate GenServers for URLQueue and URLRegistry
**Rationale**: Clear separation of concerns, easier testing and monitoring
**Alternatives Considered**:
- Single GenServer: Rejected due to potential bottleneck and complexity
- ETS tables: Rejected for initial implementation (can be added later for performance)

### 4. Database Schema Design
**Decision**: Separate tables for sites, pages, and jobs
**Rationale**: Normalized structure supports multiple crawling strategies and job tracking
```sql
crawled_sites: id, name, base_url, crawler_module, config, status
crawled_pages: id, site_id, url, title, content, metadata, crawled_at
crawl_jobs: id, site_id, status, started_at, completed_at, pages_count, errors_count
```

### 5. Crawler Implementation Pattern
**Decision**: Behavior-based crawlers with site-specific implementations
**Rationale**: Allows customization per site while maintaining consistent interface
```elixir
@callback init() :: :ok
@callback crawl(url :: String.t()) :: :ok | {:error, term()}
@callback extract_links(session :: Wallaby.Session.t()) :: [String.t()]
@callback extract_content(session :: Wallaby.Session.t()) :: map()
```

## Component Details

### Hologram Integration
- **Router Configuration**: Hologram.Router plug before Phoenix router
- **Static Assets**: Add `/hologram/` to served directories
- **Component Migration**: Convert Phoenix.Component to Hologram equivalent
- **Layout System**: Migrate from Phoenix templates to Hologram layout components

### Broadway Pipeline Configuration
```elixir
producer: [
  module: {Crawler.URLProducer, []},
  concurrency: 1  # Single producer to maintain order
],
processors: [
  default: [
    concurrency: 4,  # Configurable based on target site capacity
    min_demand: 1,
    max_demand: 3    # Limit concurrent requests per processor
  ]
]
```

### Wallaby Session Management
- Headless Chrome configuration for production
- Session pooling to reuse browser instances
- Configurable timeouts and retry strategies
- Error handling for browser crashes and network issues

### Data Storage Strategy
- Use Ecto for database operations with proper indexing
- Store raw HTML content with extracted metadata
- Implement content compression for large pages
- Add cleanup strategies for old crawl data

## Security Considerations

### Crawling Ethics and Safety
- Implement robots.txt parsing and respect
- Rate limiting per domain (configurable delays)
- User-Agent identification with contact information
- Blacklist sensitive domains and file types

### Application Security
- Input validation for crawler configurations
- SQL injection prevention in search queries
- XSS protection in content display
- Access controls for crawling management

## Performance Considerations

### Crawling Performance
- Configurable concurrency per site
- Connection pooling for HTTP requests
- Browser session reuse to reduce startup overhead
- Efficient URL deduplication with bloom filters (future enhancement)

### Database Performance
- Proper indexing on frequently queried columns (url, site_id, crawled_at)
- Pagination for large result sets
- Background jobs for data cleanup and archival
- Consider read replicas for content serving

### Frontend Performance
- Hologram's isomorphic rendering improves initial load
- Lazy loading for large content lists
- Client-side search filtering where appropriate
- Asset optimization and CDN integration

## Migration Strategy

### Phase 1: Framework Migration (Week 1-2)
1. Add Hologram dependencies and configuration
2. Migrate core components and layouts
3. Update routing and remove LiveView dependencies
4. Test basic application functionality

### Phase 2: Crawling System (Week 3-4)
1. Implement core crawling architecture
2. Create database schema and models
3. Build basic crawler with example site
4. Add supervision and error handling

### Phase 3: User Interface (Week 5-6)
1. Build Hologram pages for content management
2. Implement search and filtering
3. Add crawling job management interface
4. Performance testing and optimization

### Rollback Plan
- Maintain LiveView code in feature branch until migration complete
- Database migrations are reversible
- Hologram can be disabled by reverting router configuration
- Independent deployment of crawling system allows partial rollback

## Monitoring and Observability

### Crawling Metrics
- Pages crawled per minute/hour
- Error rates by site and error type
- Queue depth and processing latency
- Browser resource usage (memory, CPU)

### Application Metrics
- Page load times with Hologram
- Database query performance
- Memory usage of GenServer processes
- User interaction patterns

### Alerting
- Crawling system failures or high error rates
- Database connectivity issues
- Disk space usage for crawled content
- Browser process crashes

## Open Questions

1. **Content Storage Limits**: How long should we retain crawled content? Should we implement automatic archival?

2. **Multi-tenant Crawling**: Do we need to support multiple users with separate crawling configurations?

3. **Content Processing**: Should we implement any content analysis (duplicate detection, summary generation) in the initial version?

4. **Deployment Strategy**: Should we use containerization for easier Chrome/ChromeDriver management?

5. **Scaling Strategy**: At what point would we need to distribute crawling across multiple nodes?

## Future Enhancements

- Advanced content deduplication using content hashing
- Distributed crawling across multiple application instances  
- Machine learning for content categorization and analysis
- Integration with external APIs for content enrichment
- Real-time notifications for crawling events
- Advanced scheduling and crawling strategies (depth-first, breadth-first)