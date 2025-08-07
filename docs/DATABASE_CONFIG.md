# Database Configuration

## Overview

Glitch Cube uses PostgreSQL with PostGIS extension for all environments. Database configuration is centralized in `/config/database_config.rb` to ensure consistency across all components.

## Configuration Hierarchy

The database configuration follows this priority order:

1. **CI Environment**: `DATABASE_URL` environment variable (provided by GitHub Actions)
2. **Explicit DATABASE_URL**: If set in environment
3. **database.yml with defaults**: Standard Rails-style configuration with sensible defaults

## Default Configuration

### Local Development & Test
- **Host**: `localhost`
- **Port**: `5432`
- **Username**: `postgres`
- **Password**: `postgres`
- **Database**: `glitchcube_development` or `glitchcube_test`

### Production
- Configure via environment variables or `database.yml`

## Environment Variables

Optional environment variables to override defaults:
```bash
DATABASE_HOST=localhost       # Database host
DATABASE_PORT=5432            # Database port
DATABASE_USER=postgres        # Database username
DATABASE_PASSWORD=postgres    # Database password
DB_POOL_SIZE=5               # Connection pool size
```

Or use a single DATABASE_URL:
```bash
DATABASE_URL=postgresql://user:pass@host:5432/database
```

## Components Using Database

### 1. Sinatra Application (`app.rb`)
- Loads `database_config.rb` on startup
- Configures ActiveRecord connection
- Uses connection pool for web requests

### 2. Sidekiq Workers
- Loads database config via `sidekiq_database.rb` initializer
- Each worker gets database connection from pool
- Configured in `config/initializers/sidekiq_database.rb`

### 3. Rake Tasks
- Database tasks load config via `db:load_config`
- Migrations use centralized configuration
- Console tasks get proper database connection

### 4. Test Suite
- Uses `glitchcube_test` database
- Configured in `spec_helper.rb`
- Automatic setup in CI via DATABASE_URL

### 5. GitHub Actions CI
- Provides DATABASE_URL for PostgreSQL service
- Format: `postgresql://postgres:postgres@localhost:5432/glitchcube_test`
- No manual configuration needed

## Database Setup

### Local Development
```bash
# Create database
bundle exec rake db:create

# Run migrations
bundle exec rake db:migrate

# Load seed data (if any)
bundle exec rake db:seed
```

### Test Environment
```bash
# Create test database
RACK_ENV=test bundle exec rake db:create

# Run migrations
RACK_ENV=test bundle exec rake db:migrate
```

### Production
```bash
# Use production database URL
DATABASE_URL=postgresql://user:pass@host/db bundle exec rake db:migrate
```

## PostGIS Extension

The app uses PostGIS for geospatial features (GPS tracking, location services):

1. Database.yml specifies `adapter: postgis`
2. The centralized config handles PostGIS → PostgreSQL adapter conversion
3. PostGIS extension is created automatically via migrations

## Connection Pooling

- **Default pool size**: 5 connections
- **Sidekiq**: Uses separate connection pool
- **Web requests**: Share connection pool
- Configure via `DB_POOL_SIZE` environment variable

## Troubleshooting

### "Database does not exist"
```bash
bundle exec rake db:create
```

### "Migrations are pending"
```bash
bundle exec rake db:migrate
```

### Connection refused
- Check PostgreSQL is running: `pg_isready`
- Verify host/port: `psql -h localhost -p 5432 -U postgres -l`
- Check credentials: `psql -U postgres -d glitchcube_development`

### Sidekiq database errors
- Restart Sidekiq after database changes
- Check pool size is sufficient for worker count
- Verify `sidekiq_database.rb` is loaded

## Best Practices

1. **Always use centralized config** - Don't hardcode database connections
2. **Use DATABASE_URL in production** - Single source of truth
3. **Keep pool size reasonable** - 5-10 for most use cases
4. **Test migrations locally first** - Before deploying to production
5. **Monitor connection usage** - Avoid connection pool exhaustion