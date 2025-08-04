# Persistence Options for Glitch Cube

Desiru provides an optional persistence layer for tracking module executions, performance metrics, and optimization history. You can choose between different storage backends based on your needs.

## Quick Summary

- **No persistence needed?** Just use Redis for Sidekiq jobs - no data model required
- **Want analytics?** Use SQLite (default) - zero configuration
- **Production scale?** Use PostgreSQL - better for 24/7 operations

## Storage Options

### 1. No Persistence (Redis Only)

**Best for:** Minimal setup, development, testing

```bash
# Just run the standard docker-compose
docker-compose up -d
```

- Uses Redis for Sidekiq background jobs only
- No conversation history or analytics
- Simplest setup with least resource usage

### 2. SQLite (Default)

**Best for:** Single installation, easy backup, low maintenance

```bash
# Automatically configured when persistence is enabled
# Data stored in data/glitchcube.db
docker-compose up -d
```

Features:
- Zero configuration
- Single file database (easy backup)
- Good for single Glitch Cube installation
- Automatic migrations on startup

### 3. PostgreSQL (Production)

**Best for:** 24/7 operation, advanced analytics, multi-cube future

```bash
# Use the PostgreSQL overlay
docker-compose -f docker-compose.yml -f docker-compose.postgres.yml up -d
```

Features:
- Better concurrent performance
- Advanced querying capabilities
- Scalable for future multi-cube setups
- Professional monitoring tools available

## What Gets Stored?

When persistence is enabled, Desiru tracks:

1. **Module Executions**
   - Input/output pairs
   - Response times
   - Success/failure status
   - Model used

2. **Performance Metrics**
   - Average response times
   - Success rates by module
   - Token usage (if available)

3. **Optimization History**
   - Training examples
   - Prompt evolution
   - A/B test results

## Configuration

### Environment Variables

```bash
# For SQLite (default)
# No configuration needed - uses data/glitchcube.db

# For PostgreSQL
DATABASE_URL=postgres://glitchcube:password@postgres:5432/glitchcube
POSTGRES_PASSWORD=your_secure_password
```

### Persistence API

The app provides analytics endpoints in development mode:

```bash
# View recent conversations
curl http://localhost:4567/api/v1/analytics/conversations?limit=20

# Get module performance stats
curl http://localhost:4567/api/v1/analytics/modules/ConversationModule
```

## Recommendations

### For Art Installation (Your Use Case)

Since you mentioned "we don't really have a data model", I recommend:

1. **Start with Redis only** - Gets you running quickly
2. **Add SQLite later** - If you want to analyze conversations
3. **Consider PostgreSQL** - Only if you need 24/7 reliability

### Benefits of Adding Persistence

Even without a complex data model, persistence helps with:
- Understanding how visitors interact
- Tracking which personalities work best
- Debugging conversation issues
- Creating "memories" for returning visitors

### Migration Path

```bash
# Start simple
docker-compose up -d  # Redis only

# Add persistence later
# 1. Update config/persistence.rb if needed
# 2. Restart the app
# 3. Tables auto-create on first run
```

## Backup Strategies

### SQLite
```bash
# Simple file copy
cp data/glitchcube.db backups/glitchcube-$(date +%Y%m%d).db
```

### PostgreSQL
```bash
# Database dump
docker exec glitchcube_postgres pg_dump -U glitchcube glitchcube > backup.sql
```

## Performance Impact

- **Redis only**: Negligible impact
- **SQLite**: ~5-10ms per conversation tracking
- **PostgreSQL**: ~3-5ms per conversation tracking

For an art installation with single-user interactions, any option works well.