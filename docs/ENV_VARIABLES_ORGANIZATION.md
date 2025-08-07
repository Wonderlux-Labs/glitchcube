# Environment Variables Organization

This document describes which environment variables belong in which `.env` files and why, following the principle that all ENV access should go through `GlitchCube.config`.

## Configuration Layers

Environment variables are loaded in priority order (lowest to highest):
1. `.env.defaults` - Default values that rarely need to be overridden
2. `.env.{environment}` - Environment-specific overrides (test, development, production)
3. `.env` - Local overrides and secrets
4. Actual ENV variables - Runtime overrides (e.g., from Docker, systemd, or CI)

## .env.defaults
**Purpose**: Sensible defaults that work for most scenarios

```bash
# Application Defaults
PORT=4567
APP_VERSION=1.0.0
DEFAULT_AI_MODEL=google/gemini-2.5-flash
AI_TEMPERATURE=0.8
AI_MAX_TOKENS=200
MAX_SESSION_MESSAGES=10

# System Defaults
TZ=America/Los_Angeles
DEFAULT_PERSONALITY=buddy
DEVICE_ID=glitch_cube_001
INSTALLATION_LOCATION=Black Rock City

# Service URLs (Development)
REDIS_URL=redis://localhost:6379/0
HA_URL=http://glitch.local:8123
MOCK_HOME_ASSISTANT=false

# Optional Services
UPTIME_KUMA_PUSH_URL=https://status.wlux.casa/api/push/Bf8nrx6ykq

# VM Configuration
HASS_VM_HOST=localhost
HASS_VM_USER=homeassistant

# Self-Healing
SELF_HEALING=DRY_RUN
SELF_HEALING_MIN_CONFIDENCE=0.85
SELF_HEALING_ERROR_THRESHOLD=2

# Required Configuration (commented out - must be set elsewhere)
# OPENROUTER_API_KEY=your-api-key-here  # Required for AI functionality
# HOME_ASSISTANT_TOKEN=your-token-here  # Required unless MOCK_HOME_ASSISTANT=true
# SESSION_SECRET=your-secret-here       # Auto-generated if not provided
```

## .env.test
**Purpose**: Test environment configuration

```bash
# Environment
RACK_ENV=test
APP_ENV=test

# Test Database
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/glitchcube_test
DB_POOL_SIZE=5

# Mock Services
MOCK_HOME_ASSISTANT=true

# Test Secrets (can be overridden by CI)
OPENROUTER_API_KEY=test-api-key
HOME_ASSISTANT_TOKEN=test-ha-token
SESSION_SECRET=test_session_secret_for_specs_only_must_be_at_least_64_characters_long_for_rack_session
HELICONE_API_KEY=test-helicone-key

# Test Device
DEVICE_ID=test_cube_001
INSTALLATION_LOCATION=Test Gallery
```

## .env.development
**Purpose**: Development environment overrides (if needed)

```bash
# Development specific settings
# Usually empty - uses defaults
```

## .env.production
**Purpose**: Production environment configuration

```bash
# Environment
RACK_ENV=production

# Production Database
DATABASE_URL=postgresql://user:pass@host:5432/glitchcube_production

# Real Home Assistant
MOCK_HOME_ASSISTANT=false
HOME_ASSISTANT_URL=http://192.168.1.100:8123

# Production settings
SELF_HEALING=OFF  # or DRY_RUN, never YOLO in production
```

## .env (Local Only - Never Committed)
**Purpose**: Local secrets and personal overrides

```bash
# Your actual API keys
OPENROUTER_API_KEY=sk-or-v1-your-actual-key
HELICONE_API_KEY=sk-helicone-your-actual-key
HOME_ASSISTANT_TOKEN=your-actual-ha-token

# Generated session secret
SESSION_SECRET=generated-64-char-hex-string

# Optional personal tokens
GITHUB_TOKEN=github_pat_your_token
```

## Access Pattern

All environment variables should be accessed through `GlitchCube.config`:

```ruby
# Good - centralized configuration
GlitchCube.config.openrouter_api_key
GlitchCube.config.redis_url
GlitchCube.config.monitoring.uptime_kuma_push_url

# Bad - direct ENV access
ENV['OPENROUTER_API_KEY']
ENV.fetch('REDIS_URL', 'default')
```

## Config Module Structure

The `config/initializers/config.rb` defines all available configuration:

- **Core**: API keys, ports, database URLs
- **Home Assistant**: URL, token, mock flag
- **Monitoring**: Uptime Kuma URL
- **Device**: ID, location, version
- **System**: Timezone, passwords, tokens
- **AI**: Models, temperature, token limits
- **GPS**: Device tracker entity
- **Deployment**: VM settings, tokens
- **Self-Healing**: Mode, thresholds

## Testing

Tests should mock the config, not ENV:

```ruby
# Good
allow(GlitchCube.config).to receive(:redis_url).and_return('redis://test:6379')
allow(GlitchCube.config.monitoring).to receive(:uptime_kuma_push_url).and_return(nil)

# Bad
allow(ENV).to receive(:[]).with('REDIS_URL').and_return('redis://test:6379')
```

## Required vs Optional Variables

### Required Variables (ENV.fetch without default)
These will cause the application to fail fast on startup if missing:

- **OPENROUTER_API_KEY** - Required for AI functionality (except in test mode)
- **HOME_ASSISTANT_TOKEN** - Required unless `MOCK_HOME_ASSISTANT=true`

### Optional Variables with Defaults
These have sensible defaults but can be overridden:

- All others in `.env.defaults`
- **SESSION_SECRET** - Auto-generated if not provided
- **DATABASE_URL**, **REDIS_URL**, etc.

### Test Environment Exceptions
Test environment provides defaults for required variables to ensure tests pass without real API keys.

## Migration Checklist

When adding a new environment variable:

1. ✅ Add to `config/initializers/config.rb`
2. ✅ Use `ENV.fetch('VAR')` (no default) for required vars
3. ✅ Use `ENV.fetch('VAR', 'default')` for optional vars  
4. ✅ Add default to `.env.defaults` if applicable
5. ✅ Update service to use `GlitchCube.config.xxx`
6. ✅ Update tests to mock config, not ENV
7. ✅ Document in `ENVIRONMENT_VARIABLES.md`