# Environment Configuration

## Overview

Glitch Cube uses a hierarchical environment configuration system with Dotenv for managing environment variables.

## Configuration Priority Order

Environment variables are loaded with the following priority (highest to lowest):

1. **Manually set ENV variables** - Already set in shell or by system
2. **`.env`** - User-specific overrides (not in git)
3. **`.env.{RACK_ENV}`** - Environment-specific settings (.env.production, .env.development, .env.test)
4. **`.env.defaults`** - Base default values for all environments

## Environment Files

### `.env.defaults`
Base configuration with sensible defaults for all environments. This file is checked into git and contains non-sensitive default values.

### `.env.development`
Development-specific settings:
- Database: `glitchcube_development`
- Redis: `redis://localhost:6379/0`
- Port: 4567
- Puma workers: 0 (single process)

### `.env.test`
Test environment settings:
- Database: `glitchcube_test`
- Mock services enabled
- VCR cassettes for external API calls

### `.env.production`
Production settings for Mac Mini deployment:
- Database: `glitchcube_production`
- Self-healing mode enabled
- Log level: info

### `.env` (User Override)
Personal overrides that apply to all environments. This file is:
- **NOT** checked into git (in .gitignore)
- Used for personal API keys and local configuration
- Overrides any setting from other .env files

## Key Environment Variables

### Database Configuration
```bash
DATABASE_HOST=localhost       # Database server host
DATABASE_PORT=5432            # PostgreSQL port
DATABASE_USER=postgres        # Database username
DATABASE_PASSWORD=postgres    # Database password
DATABASE_NAME=glitchcube_*    # Override database name
DATABASE_URL=postgresql://... # Full connection string (overrides all above)
DB_POOL_SIZE=5               # Connection pool size
```

### Application Settings
```bash
RACK_ENV=production          # Environment (development/test/production)
PORT=4567                    # Web server port
PUMA_WORKERS=0              # Number of Puma workers (0 = single process)
PUMA_MIN_THREADS=1          # Minimum threads per worker
PUMA_MAX_THREADS=5          # Maximum threads per worker
```

### Redis & Background Jobs
```bash
REDIS_URL=redis://localhost:6379/0  # Redis connection URL
```

### Feature Flags
```bash
SIMULATE_CUBE_MOVEMENT=false  # Enable GPS simulation
SELF_HEALING_MODE=true        # Enable self-healing error recovery
LOG_LEVEL=info               # Logging verbosity (debug/info/warn/error)
```

### API Keys (in .env only, not in git)
```bash
OPENROUTER_API_KEY=your_key_here
HOME_ASSISTANT_TOKEN=your_token_here
SESSION_SECRET=your_64_char_secret_here
```

## Running the Application

### Development (Local)
```bash
# Using foreman with development Procfile
foreman start -f Procfile.dev

# Or manually
RACK_ENV=development bundle exec ruby app.rb
RACK_ENV=development bundle exec sidekiq -r ./config/sidekiq_boot.rb
```

### Production (Mac Mini)
```bash
# Using foreman with production Procfile
foreman start

# The Procfile automatically sets RACK_ENV=production
```

### Test Suite
```bash
# Tests automatically use .env.test
bundle exec rspec

# CI overrides with DATABASE_URL
CI=true DATABASE_URL=postgresql://... bundle exec rspec
```

## How Dotenv Loading Works

Dotenv uses a "first wins" strategy - the first file to define a variable wins. That's why we load files in reverse priority order:

```ruby
# In app.rb and sidekiq_boot.rb
Dotenv.load(
  '.env',                      # Highest priority (user overrides)
  ".env.#{ENV['RACK_ENV']}",  # Environment-specific
  '.env.defaults'              # Lowest priority (defaults)
)
```

## Foreman Process Management

Foreman is included in the Gemfile for development/test environments:

```ruby
gem 'foreman', '~> 0.88', require: false
```

### Procfile (Production)
```
web: RACK_ENV=production PORT=4567 PUMA_WORKERS=0 bundle exec rackup
worker: RACK_ENV=production bundle exec sidekiq -r ./config/sidekiq_boot.rb
```

### Procfile.dev (Development)
```
web: RACK_ENV=${RACK_ENV:-development} bundle exec puma
worker: RACK_ENV=${RACK_ENV:-development} bundle exec sidekiq -r ./config/sidekiq_boot.rb
```

## Database Connection Precedence

1. `DATABASE_URL` environment variable (highest priority)
2. `DATABASE_NAME` + other DATABASE_* variables
3. Configuration from `database.yml`
4. Default: `glitchcube_{environment}`

## Troubleshooting

### Wrong Database Being Used
1. Check `RACK_ENV` is set correctly
2. Verify `.env.{environment}` file exists
3. Check `DATABASE_NAME` or `DATABASE_URL` isn't overriding
4. Restart all processes after changes

### Environment Variables Not Loading
1. Check file exists and has correct name
2. Verify Dotenv.load order in app.rb
3. Check for typos in variable names
4. Use `puts ENV['VAR_NAME']` to debug

### Sidekiq Using Different Settings
1. Ensure Procfile sets `RACK_ENV` for worker
2. Check sidekiq_boot.rb loads environment files
3. Verify database configuration in boot file

## Best Practices

1. **Never commit `.env`** - Keep personal settings local
2. **Use `.env.defaults`** for non-sensitive defaults
3. **Environment-specific files** for environment settings
4. **Document new variables** in .env.example
5. **Restart processes** after changing environment files
6. **Use foreman** for consistent process management