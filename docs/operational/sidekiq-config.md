# Sidekiq Configuration

## Overview

Glitch Cube uses Sidekiq for background job processing with Redis as the queue backend.

## Queue Configuration

### Queue Priorities
- **critical** (weight: 3) - Urgent operations
- **default** (weight: 2) - Normal priority jobs
- **low** (weight: 1) - Background maintenance

### Worker Configuration
- **Concurrency**: 5 workers
- **Timeout**: 25 seconds
- **Max retries**: 25
- **Dead job retention**: 1000 jobs max

## Database Configuration

Sidekiq workers load database configuration via `/config/sidekiq_boot.rb` which ensures proper PostgreSQL credentials are used before loading the application.

### Boot Sequence
1. Set RACK_ENV (defaults to development)
2. Load environment variables from .env files
3. Configure database with centralized config
4. Load main application
5. Load Sidekiq configuration

## Scheduled Jobs (Cron)

Jobs are defined in `/config/sidekiq_cron.yml`:

| Job | Schedule | Queue | Purpose |
|-----|----------|-------|---------|
| simulate_cube_movement_worker | Every 5 minutes | default | Simulate GPS movement (when SIMULATE_CUBE_MOVEMENT=true) |
| memory_consolidation | Every 6 hours | low | Consolidate and optimize memory storage |
| host_registration | Every 5 minutes | default | Register Glitch Cube IP with Home Assistant |
| personality_memory | Every 30 minutes | low | Extract memories from conversations |

## Active Workers

### Default Queue
- `HostRegistrationWorker` - IP registration with Home Assistant
- `InitialHostRegistrationWorker` - Initial setup registration
- `MissedDeploymentWorker` - Handle deployment notifications
- `SimulateCubeMovementWorker` - GPS simulation

### Low Queue
- `PersonalityMemoryJob` - Extract conversation memories
- `MemoryConsolidationJob` - Optimize memory storage
- `ConversationSummaryJob` - Summarize conversations

## Running Sidekiq

### Development
```bash
# Using foreman with Procfile.dev
foreman start -f Procfile.dev

# Or directly
bundle exec sidekiq -r ./config/sidekiq_boot.rb -C config/sidekiq.yml
```

### Production (Mac Mini)
```bash
# Using foreman with Procfile
foreman start

# The Procfile runs:
# worker: bundle exec sidekiq -r ./config/sidekiq_boot.rb -C config/sidekiq.yml
```

## Redis Configuration

- **Default URL**: `redis://localhost:6379/0`
- **Namespace**: `glitchcube`
- **Environment variable**: `REDIS_URL`

## Monitoring

### Sidekiq Web UI
Available at `/sidekiq` when mounted in routes (requires authentication in production)

### Logging
- Job start/completion logged to console
- Beacon-specific jobs have additional logging via `BeaconLoggingMiddleware`
- Cron job status displayed on startup

## Troubleshooting

### Database Connection Issues
If Sidekiq uses wrong database credentials:
1. Ensure using `sidekiq_boot.rb` in Procfile
2. Check DATABASE_USER and DATABASE_PASSWORD env vars
3. Verify `/config/database_config.rb` is loaded before app

### Jobs Not Running
1. Check Redis is running: `redis-cli ping`
2. Verify cron syntax in `sidekiq_cron.yml`
3. Check job class names match actual classes
4. Look for errors in Sidekiq logs

### Queue Backlog
1. Check queue sizes: `redis-cli llen glitchcube:queue:default`
2. Increase concurrency if needed (edit sidekiq.yml)
3. Monitor job execution times