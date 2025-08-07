# Environment Variables Documentation

This document lists all environment variables used by the Glitch Cube application.

## Required Variables

### API Keys

| Variable | Description | Example |
|----------|-------------|---------|
| `OPENROUTER_API_KEY` | OpenRouter API key for AI model access | `sk-or-v1-abcd...` |
| `HA_TOKEN` | Home Assistant long-lived access token | `eyJ0eXAiOiJKV1...` |
| `SESSION_SECRET` | 64-character hex string for session encryption | Generate with `openssl rand -hex 64` |
| `MASTER_PASSWORD` | Single password for all services (Portainer, Postgres, etc) | `glitchcube123` |

## Optional Variables

### Application Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `RACK_ENV` | Application environment | `development` | `production`, `development`, `test` |
| `PORT` | Port for Sinatra to listen on | `4567` | `4567` |
| `DEFAULT_AI_MODEL` | Default AI model to use | `google/gemini-2.5-flash` | `anthropic/claude-3-opus`, `openai/gpt-4` |
| `LOG_LEVEL` | Logging verbosity | `info` | `debug`, `info`, `warn`, `error` |
| `TZ` | Timezone for the application | `UTC` | `America/Chicago`, `Europe/London` |

### Home Assistant Integration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `HA_URL` | Home Assistant base URL | `http://localhost:8123` | `http://homeassistant.local:8123` |
| `HOME_ASSISTANT_URL` | Alias for HA_URL | - | Same as HA_URL |
| `HOME_ASSISTANT_TOKEN` | Alias for HA_TOKEN | - | Same as HA_TOKEN |
| `MOCK_HOME_ASSISTANT` | Enable mock HA for development | `false` | `true` |

### Database Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `DATABASE_URL` | Database connection string | `sqlite://data/glitchcube.db` | `postgres://user:pass@host/db` |
| `POSTGRES_PASSWORD` | PostgreSQL password (uses MASTER_PASSWORD) | `${MASTER_PASSWORD}` | - |
| `POSTGRES_USER` | PostgreSQL username | `glitchcube` | `glitchcube` |
| `POSTGRES_DB` | PostgreSQL database name | `glitchcube` | `glitchcube_production` |

### Redis Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `REDIS_URL` | Redis connection URL | `redis://localhost:6379/0` | `redis://redis:6379/0` |

### Device Identification

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `DEVICE_ID` | Unique identifier for this cube | `glitch_cube_001` | `cube_gallery_west` |
| `INSTALLATION_LOCATION` | Physical location description | `gallery_main` | `MoMA_Floor_2` |

### External Monitoring (Optional)

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `UPTIME_KUMA_PUSH_URL` | Uptime Kuma push monitor URL | - | `https://uptime.example.com/api/push/xyz123` |

### Development Only

| Variable | Description | Default |
|----------|-------------|---------|
| `DEVELOPMENT_MODE` | Enable development features | `false` |

## Docker Compose Variables

These are used in docker-compose.yml files:

| Variable | Description | Used In |
|----------|-------------|---------|
| `MASTER_PASSWORD` | Master password for all services | All password-protected services |
| `PORTAINER_ADMIN_PASSWORD` | Portainer admin password (uses MASTER_PASSWORD) | `docker-compose.yml` |
| `POSTGRES_PASSWORD` | PostgreSQL container password (uses MASTER_PASSWORD) | `docker-compose.postgres.yml` |
| `DEFAULT_AI_MODEL` | Passed to all containers | All services |

## Example .env File

```bash
# Required
OPENROUTER_API_KEY=sk-or-v1-your-key-here
HA_TOKEN=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...
SESSION_SECRET=a1b2c3d4e5f6... (64 hex characters)
MASTER_PASSWORD=glitchcube123  # Change this!

# Optional but recommended
DEFAULT_AI_MODEL=google/gemini-2.5-flash
DEVICE_ID=glitch_cube_001
INSTALLATION_LOCATION=gallery_main
TZ=America/Chicago

# Redis (Docker service name in production)
REDIS_URL=redis://redis:6379/0

# Home Assistant
HA_URL=http://localhost:8123

# Optional Uptime Kuma push monitoring
# UPTIME_KUMA_PUSH_URL=https://uptime.example.com/api/push/xyz123
```

## Environment-Specific Settings

### Production
- `RACK_ENV=production`
- `DATABASE_URL=sqlite://data/production/glitchcube.db`
- `REDIS_URL=redis://redis:6379/0`

### Development
- `RACK_ENV=development`
- `DATABASE_URL=sqlite://data/development/glitchcube.db`
- `MOCK_HOME_ASSISTANT=true` (optional)

### Test
- `RACK_ENV=test`
- `DATABASE_URL=sqlite::memory:`
- `MOCK_HOME_ASSISTANT=true`