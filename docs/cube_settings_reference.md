# Cube::Settings Configuration Reference

This document provides a comprehensive reference for all configuration settings available through the `Cube::Settings` module.

## Usage

Access any setting through the `Cube::Settings` module:

```ruby
# Examples
Cube::Settings.simulate_cube_movement?  # => true/false
Cube::Settings.openrouter_api_key       # => "sk-or-..."
Cube::Settings.database_type            # => :sqlite/:mariadb/:postgres
```

## Feature Toggles

| Method | ENV Variable | Description | Default |
|--------|--------------|-------------|---------|
| `simulate_cube_movement?` | `SIMULATE_CUBE_MOVEMENT` | Enable GPS movement simulation for testing | `true` in development, `false` in production |
| `mock_home_assistant?` | `MOCK_HOME_ASSISTANT` | Use mock Home Assistant endpoints | `false` |
| `disable_circuit_breakers?` | `DISABLE_CIRCUIT_BREAKERS` | Disable circuit breakers (testing only) | `false` |
| `mac_mini_deployment?` | `MAC_MINI_DEPLOYMENT` | Running on Mac Mini deployment | `false` |

## Environment

| Method | ENV Variable | Description | Default |
|--------|--------------|-------------|---------|
| `rack_env` | `RACK_ENV` | Current environment (development/test/production) | `development` |
| `development?` | `RACK_ENV` | Check if in development environment | - |
| `test?` | `RACK_ENV` | Check if in test environment | - |
| `production?` | `RACK_ENV` | Check if in production environment | - |
| `deployment_mode` | Multiple | Returns :mac_mini, :docker, :production, or :development | `:development` |
| `docker_deployment?` | `DOCKER_CONTAINER` | Detects if running in Docker container | `false` |

## Application Settings

| Method | ENV Variable | Description | Default |
|--------|--------------|-------------|---------|
| `app_root` | `APP_ROOT` | Application root directory | `Dir.pwd` |
| `session_secret` | `SESSION_SECRET` | Session encryption key | `nil` |
| `port` | `PORT` | Web server port | `4567` |
| `timezone` | `TZ` | System timezone | `America/Los_Angeles` |

## Logging Configuration

| Method | ENV Variable | Description | Default |
|--------|--------------|-------------|---------|
| `log_level` | `LOG_LEVEL` | Logging verbosity (DEBUG, INFO, WARN, ERROR, FATAL) | `DEBUG` (dev), `INFO` (prod), `WARN` (test) |
| `default_log_level` | - | Returns environment-appropriate default log level | Based on environment |

## API Keys and Tokens

| Method | ENV Variable | Description | Default |
|--------|--------------|-------------|---------|
| `openrouter_api_key` | `OPENROUTER_API_KEY` | OpenRouter API key for AI models | `nil` |
| `openai_api_key` | `OPENAI_API_KEY` | OpenAI API key | `nil` |
| `anthropic_api_key` | `ANTHROPIC_API_KEY` | Anthropic API key | `nil` |
| `helicone_api_key` | `HELICONE_API_KEY` | Helicone gateway API key | `nil` |
| `home_assistant_token` | `HOME_ASSISTANT_TOKEN` or `HA_TOKEN` | Home Assistant authentication token | `nil` |
| `github_webhook_secret` | `GITHUB_WEBHOOK_SECRET` | GitHub webhook verification secret | `nil` |
| `master_password` | `MASTER_PASSWORD` | Master password for admin functions | `nil` |

## URLs and Endpoints

| Method | ENV Variable | Description | Default |
|--------|--------------|-------------|---------|
| `home_assistant_url` | `HOME_ASSISTANT_URL` or `HA_URL` | Home Assistant server URL | `nil` |
| `database_url` | `DATABASE_URL` | Database connection URL | `sqlite://data/glitchcube.db` |
| `redis_url` | `REDIS_URL` | Redis server URL | `nil` |
| `ai_gateway_url` | `AI_GATEWAY_URL` | AI gateway proxy URL | `nil` |

## Database Configuration

### Database Type Detection

| Method | Description | Returns |
|--------|-------------|---------|
| `database_type` | Detects database type from DATABASE_URL | `:sqlite`, `:mariadb`, or `:postgres` |
| `using_sqlite?` | Check if using SQLite database | `true`/`false` |
| `using_mariadb?` | Check if using MariaDB/MySQL database | `true`/`false` |
| `using_postgres?` | Check if using PostgreSQL database | `true`/`false` |

### SQLite Settings

| Method | Description | Returns |
|--------|-------------|---------|
| `sqlite_path` | Path to SQLite database file (only when using SQLite) | String or `nil` |

### MariaDB Settings
*Note: These methods return `nil` when not using MariaDB*

| Method | ENV Variable | Description | Default |
|--------|--------------|-------------|---------|
| `mariadb_host` | `MARIADB_HOST` | MariaDB server hostname | `localhost` |
| `mariadb_port` | `MARIADB_PORT` | MariaDB server port | `3306` |
| `mariadb_database` | `MARIADB_DATABASE` | MariaDB database name | `glitchcube` |
| `mariadb_username` | `MARIADB_USERNAME` | MariaDB username | `glitchcube` |
| `mariadb_password` | `MARIADB_PASSWORD` | MariaDB password | `glitchcube` |
| `mariadb_url` | Generated | Complete MariaDB connection URL | Generated from above |

## AI Configuration

| Method | ENV Variable | Description | Default |
|--------|--------------|-------------|---------|
| `default_ai_model` | `DEFAULT_AI_MODEL` | Default AI model to use | `google/gemini-2.5-flash` |
| `ai_temperature` | `AI_TEMPERATURE` | AI response creativity (0.0-1.0) | `0.8` |
| `ai_max_tokens` | `AI_MAX_TOKENS` | Maximum tokens per AI response | `200` |
| `max_session_messages` | `MAX_SESSION_MESSAGES` | Max messages to keep in session | `10` |

## Device Configuration

| Method | ENV Variable | Description | Default |
|--------|--------------|-------------|---------|
| `device_id` | `DEVICE_ID` | Unique device identifier | `glitch_cube_001` |
| `installation_location` | `INSTALLATION_LOCATION` | Physical installation location | `Black Rock City` |
| `app_version` | `APP_VERSION` | Application version number | `1.0.0` |

## GPS Configuration

| Method | ENV Variable | Description | Default |
|--------|--------------|-------------|---------|
| `gps_device_tracker_entity` | `GPS_DEVICE_TRACKER_ENTITY` | Home Assistant GPS tracker entity ID | `device_tracker.glitch_cube` |
| `home_camp_time` | `HOME_CAMP_TIME` | Time-based street for home camp (e.g., '5:30') | `5:30` |
| `home_camp_street` | `HOME_CAMP_STREET` | Lettered street for home camp (e.g., 'F') | `F` |
| `home_camp_coordinates` | Calculated | Returns lat/lng coordinates for home camp | Based on time/street |

## Configuration Validation

| Method | Description |
|--------|-------------|
| `validate_production_config!` | Validates required settings for production environment |

The validation checks for:
- `OPENROUTER_API_KEY` is set
- `SESSION_SECRET` is explicitly set
- `HOME_ASSISTANT_TOKEN` is set
- `HOME_ASSISTANT_URL` is set

## Testing Support

The `Cube::Settings` module includes methods for overriding settings during tests:

| Method | Description |
|--------|-------------|
| `override!(key, value)` | Override a setting value for testing |
| `clear_overrides!` | Clear all overrides |
| `overridden?(key)` | Check if a setting has been overridden |

### Example Test Usage

```ruby
# In RSpec tests
before do
  Cube::Settings.override!(:simulate_cube_movement, true)
  Cube::Settings.override!(:mock_home_assistant, true)
end

after do
  Cube::Settings.clear_overrides!
end
```

## Environment Variable Precedence

Some settings check multiple environment variables for backwards compatibility:

1. **Home Assistant URL**: Checks `HOME_ASSISTANT_URL` first, falls back to `HA_URL`
2. **Home Assistant Token**: Checks `HOME_ASSISTANT_TOKEN` first, falls back to `HA_TOKEN`

## Conditional Settings

### Database-Specific Settings

The module intelligently handles database-specific settings:

- **SQLite**: When `DATABASE_URL` starts with `sqlite://`, only SQLite methods return values
- **MariaDB**: When `DATABASE_URL` contains `mysql` or `mariadb`, MariaDB methods return configured values
- **PostgreSQL**: When `DATABASE_URL` contains `postgres`, PostgreSQL is detected (MariaDB/SQLite methods return `nil`)

This prevents confusion by only exposing relevant configuration for the active database type.

## Usage Examples

```ruby
# Check environment
if Cube::Settings.production?
  Cube::Settings.validate_production_config!
end

# Database configuration
case Cube::Settings.database_type
when :sqlite
  puts "Using SQLite at: #{Cube::Settings.sqlite_path}"
when :mariadb
  puts "Using MariaDB at: #{Cube::Settings.mariadb_host}:#{Cube::Settings.mariadb_port}"
end

# Feature flags
if Cube::Settings.simulate_cube_movement?
  # Run GPS simulation
end

# API configuration
client = OpenRouter::Client.new(
  access_token: Cube::Settings.openrouter_api_key
)

# Deployment detection
case Cube::Settings.deployment_mode
when :docker
  # Docker-specific configuration
when :mac_mini
  # Mac Mini specific setup
when :production
  # Production optimizations
else
  # Development mode
end
```

## Required Environment Variables

### Production Requirements

The following environment variables MUST be set in production:

- `OPENROUTER_API_KEY` - Required for AI functionality
- `SESSION_SECRET` - Required for secure sessions
- `HOME_ASSISTANT_TOKEN` - Required for IoT integration
- `HOME_ASSISTANT_URL` - Required for IoT integration

### Optional but Recommended

- `REDIS_URL` - For background job processing
- `DATABASE_URL` - For persistence (defaults to SQLite)
- `UPTIME_KUMA_PUSH_URL` - For external monitoring (optional)