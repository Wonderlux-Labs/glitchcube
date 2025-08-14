# Configuration System Documentation

This document explains GlitchCube's configuration system, which provides a centralized, consistent way to manage all application settings.

## Overview

GlitchCube uses a layered configuration system with the following priority (highest to lowest):

1. **Environment Variables** - Runtime overrides (production secrets, per-environment settings)
2. **Application Defaults** - Hardcoded defaults in `config/initializers/config.rb`

This system eliminates the need for multiple `.env.defaults` files and provides a single source of truth for all configuration values.

## Required Environment Variables

**Only 2 environment variables are required for GlitchCube to function:**

| Variable | Purpose | Example |
|----------|---------|---------|
| `OPENROUTER_API_KEY` | AI model access | `sk-or-v1-abcd1234...` |
| `HOME_ASSISTANT_TOKEN` | Hardware control | `eyJ0eXAiOiJKV1Qi...` |

All other configuration has sensible defaults and can optionally be overridden.

## Configuration Access

### Using the Config Object

**✅ Correct - Use the config object:**
```ruby
# Good - uses centralized config
redis_url = GlitchCube.config.redis_url
rack_env = GlitchCube.config.rack_env
api_key = GlitchCube.config.openrouter_api_key
```

**❌ Incorrect - Direct ENV access:**
```ruby
# Bad - bypasses config system
redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379/0'
rack_env = ENV['RACK_ENV'] || 'development'
api_key = ENV['OPENROUTER_API_KEY']
```

### Nested Configuration

```ruby
# Home Assistant settings
GlitchCube.config.home_assistant.url    # => "http://100.126.250.73:8123"
GlitchCube.config.home_assistant.token  # => "your-token"

# Device information
GlitchCube.config.device.id             # => "glitch_cube_001"
GlitchCube.config.device.location       # => "Black Rock City"

# AI settings
GlitchCube.config.ai.temperature         # => 0.8
GlitchCube.config.ai.max_tokens         # => 2000
```

## Default Values

All defaults are defined in `config/initializers/config.rb`:

```ruby
DEFAULTS = {
  # Core Application
  port: 4567,
  rack_env: 'development',
  database_url: 'postgresql://localhost:5432/glitchcube_development',
  redis_url: 'redis://localhost:6379/0',
  
  # Home Assistant
  home_assistant: {
    url: 'http://100.126.250.73:8123',
    token: nil # Required
  },
  
  # AI Configuration
  ai: {
    temperature: 0.8,
    max_tokens: 2000,
    max_session_messages: 10
  },
  
  # Self-Healing
  self_healing_mode: 'DRY_RUN',
  self_healing_min_confidence: 0.85,
  
  # ... and many more
}
```

## Environment Variable Mapping

Environment variables override defaults using these mappings:

| Config Key | Environment Variable |
|------------|---------------------|
| `openrouter_api_key` | `OPENROUTER_API_KEY` |
| `redis_url` | `REDIS_URL` |
| `rack_env` | `RACK_ENV` |
| `log_level` | `LOG_LEVEL` |
| `self_healing_mode` | `SELF_HEALING` |
| `home_assistant.url` | `HOME_ASSISTANT_URL` or `HA_URL` |
| `home_assistant.token` | `HOME_ASSISTANT_TOKEN` or `HA_TOKEN` |

## Configuration Validation

The config system validates required settings on startup:

```ruby
# Automatic validation
GlitchCube.config.validate!

# Check what's missing
missing = GlitchCube::Config.check_missing_required
# => ["HOME_ASSISTANT_TOKEN"] if token not set
```

Validation errors will prevent the application from starting in production.

## Configuration Audit

Debug configuration issues with the audit method:

```ruby
audit = GlitchCube::Config.audit_defaults

audit[:required_env_vars]       # => ["OPENROUTER_API_KEY", "HOME_ASSISTANT_TOKEN"]
audit[:missing_required]        # => [] if all required vars are set
audit[:current_env_overrides]   # => ENV vars currently overriding defaults
audit[:defaults]                # => All default values
```

## Environment-Specific Settings

### Development (.env.development)
```bash
# Local Home Assistant
HOME_ASSISTANT_URL=http://localhost:8123

# Development features
DEBUG=true
LOG_LEVEL=debug
```

### Production (.env.production)
```bash
# Required secrets
OPENROUTER_API_KEY=sk-or-v1-production-key
HOME_ASSISTANT_TOKEN=eyJ-production-token

# Production optimizations
LOG_LEVEL=info
SELF_HEALING=DRY_RUN
```

### Test (.env.test)
```bash
# Test overrides
RACK_ENV=test
# Most settings use defaults or are mocked
```

## Special Cases

### Session Secret
- Auto-generates secure random value if not set
- Should be explicitly set in production for session continuity
- Set via `SESSION_SECRET` environment variable

### Database Configuration
- Uses separate `config/database_config.rb` for complex database logic
- Supports PostgreSQL with PostGIS extension
- Falls back to defaults if `DATABASE_URL` not specified

### Redis Connection
- Available via `GlitchCube.config.redis_connection`
- Automatically connects using `redis_url` setting
- Returns nil if Redis URL not configured

## Helper Methods

```ruby
# Environment predicates
GlitchCube.config.development?  # => true if RACK_ENV=development
GlitchCube.config.test?         # => true if RACK_ENV=test
GlitchCube.config.production?   # => true if RACK_ENV=production

# Feature flags
GlitchCube.config.debug?                    # => debug_mode setting
GlitchCube.config.self_healing_enabled?     # => self_healing_mode != 'OFF'
GlitchCube.config.self_healing_dry_run?     # => self_healing_mode == 'DRY_RUN'
```

## Migration from Direct ENV Access

When updating code to use the config system:

1. **Replace direct ENV calls:**
   ```ruby
   # Before
   ENV['REDIS_URL'] || 'redis://localhost:6379/0'
   
   # After
   GlitchCube.config.redis_url
   ```

2. **Use environment predicates:**
   ```ruby
   # Before
   ENV['RACK_ENV'] == 'development'
   
   # After
   GlitchCube.config.development?
   ```

3. **Access nested config:**
   ```ruby
   # Before
   ENV['HOME_ASSISTANT_URL'] || ENV['HA_URL']
   
   # After
   GlitchCube.config.home_assistant.url
   ```

## Best Practices

1. **Always use the config object** - Never access ENV directly in application code
2. **Add new settings to DEFAULTS** - Don't put defaults in ENV files
3. **Use validation** - Add required settings to the validation method
4. **Document new settings** - Update this file when adding configuration options
5. **Test with defaults** - Ensure your code works with default values
6. **Use environment predicates** - Don't string-compare rack_env

## Troubleshooting

### Configuration Not Loading
1. Check that `config/environment.rb` is loading dotenv correctly
2. Verify `.env` file exists and is readable
3. Use `GlitchCube::Config.audit_defaults` to debug

### Missing Required Variables
1. Check the output of `GlitchCube::Config.check_missing_required`
2. Ensure ENV variables are set in your shell
3. Verify .env file contains required keys

### Override Not Working
1. Check the ENV_MAPPINGS in `config/initializers/config.rb`
2. Verify ENV variable name matches exactly
3. Restart application after changing ENV variables

### Legacy Settings
Some code still uses `Cube::Settings` - this is a legacy system that will be deprecated. New code should always use `GlitchCube.config`.

## Security Notes

- **Never commit secrets** - Use .env files for local development only
- **Use strong session secrets** - Generate with `SecureRandom.hex(64)`
- **Validate in production** - Always check required settings on startup
- **Filter logs** - Sensitive config values should not appear in logs