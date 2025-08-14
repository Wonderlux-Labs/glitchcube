# Environment Variables Documentation

**📚 For comprehensive configuration guidance, see [CONFIGURATION.md](CONFIGURATION.md)**

This document lists all environment variables used by the Glitch Cube application.

> **Note**: As of January 2025, GlitchCube uses a centralized configuration system. Most settings have sensible defaults and only 2 environment variables are required. All defaults are defined in `config/initializers/config.rb` instead of `.env.defaults` files.

## Required Variables

**Only 2 environment variables are truly required:**

| Variable | Description | Example |
|----------|-------------|---------|
| `OPENROUTER_API_KEY` | OpenRouter API key for AI model access | `sk-or-v1-abcd...` |
| `HOME_ASSISTANT_TOKEN` | Home Assistant long-lived access token | `eyJ0eXAiOiJKV1...` |

### Additional Production Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SESSION_SECRET` | 64-character hex string for session encryption (auto-generated if not set) | Generate with `openssl rand -hex 64` |

## Optional Variables

### Application Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `RACK_ENV` | Application environment | `development` | `production`, `development`, `test` |
| `PORT` | Port for Sinatra to listen on | `4567` | `4567` |
| `DEFAULT_AI_MODEL` | Default AI model to use | `anthropic-claude-sonnet-4` | `qwen/qwen3-coder` |
| `LOG_LEVEL` | Logging verbosity | `info` | `debug`, `info`, `warn`, `error` |
| `TZ` | Timezone for the application | `America/Los_Angeles` | `America/Chicago`, `Europe/London` |

### Home Assistant Integration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `HOME_ASSISTANT_URL` | Home Assistant base URL | `http://100.126.250.73:8123` | `http://homeassistant.local:8123` |
| `HA_URL` | Alias for HOME_ASSISTANT_URL | - | Same as HOME_ASSISTANT_URL |
| `HA_TOKEN` | Alias for HOME_ASSISTANT_TOKEN | - | Same as HOME_ASSISTANT_TOKEN |

### Database Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `DATABASE_URL` | Database connection string | `postgresql://localhost:5432/glitchcube_development` | `postgres://user:pass@host/db` |

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
| `UPTIME_KUMA_PUSH_URL` | Uptime Kuma push monitor URL | `https://status.wlux.casa/api/push/Bf8nrx6ykq` | `https://uptime.example.com/api/push/xyz123` |

### Self-Healing System

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `SELF_HEALING` | Self-healing error handler mode | `DRY_RUN` | `OFF`, `DRY_RUN`, `YOLO` |
| `SELF_HEALING_MIN_CONFIDENCE` | Minimum confidence for auto-fixes | `0.85` | `0.0` to `1.0` |
| `SELF_HEALING_ERROR_THRESHOLD` | Error count before healing triggers | `2` | Integer |

### Development & Debugging

| Variable | Description | Default |
|----------|-------------|---------|
| `DEBUG` | Enable debug mode | `false` |
| `CONVERSATION_TRACING` | Enable conversation tracing | `false` |
| `ENABLE_CIRCUIT_BREAKERS` | Force enable circuit breakers in test | `false` |
| `ENABLE_RETRIES` | Force enable retries in test | `false` |

## Minimal .env File

**Only 2 variables required for basic operation:**

```bash
# Required - AI functionality
OPENROUTER_API_KEY=sk-or-v1-your-key-here

# Required - Hardware control  
HOME_ASSISTANT_TOKEN=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...
```

## Typical Production .env File

```bash
# Required
OPENROUTER_API_KEY=sk-or-v1-your-production-key
HOME_ASSISTANT_TOKEN=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...

# Recommended for production
SESSION_SECRET=a1b2c3d4e5f6789... # Generate with: openssl rand -hex 64
RACK_ENV=production

# Optional overrides
LOG_LEVEL=info
SELF_HEALING=DRY_RUN
HOME_ASSISTANT_URL=http://your-ha-instance:8123
```

## Environment-Specific Settings

### Production
- `RACK_ENV=production`
- `DATABASE_URL=postgresql://localhost:5432/glitchcube_production`
- `SESSION_SECRET=<explicit-value>` (recommended)
- `SELF_HEALING=DRY_RUN` (safe default)

### Development  
- `RACK_ENV=development` (default)
- `DATABASE_URL=postgresql://localhost:5432/glitchcube_development` (default)
- `DEBUG=true` (optional)
- `LOG_LEVEL=debug` (optional)

### Test
- `RACK_ENV=test`
- Uses defaults with automatic test adaptations
- Circuit breakers and external calls disabled automatically

## Configuration Best Practices

1. **Minimal ENV files** - Only override what you need to change
2. **Use defaults** - Let the config system provide sensible defaults  
3. **Required only** - Only 2 variables are actually required
4. **Security** - Never commit real API keys or tokens
5. **Validation** - Config system validates required settings on startup

For complete configuration documentation, see [CONFIGURATION.md](CONFIGURATION.md).