# 🎲 Glitchcube Project Guide

## Overview
Glitchcube is an autonomous interactive art installation for Burning Man - a self-contained "smart cube" that engages with participants through conversation, requests transportation, and builds relationships over multi-day events. It's a physical LED cube with AI personalities that responds to voice interactions, environmental sensors, and can engage in conversations with different personas (Buddy, Jax, Lomi, Zorp).

## Architecture

### Core Stack
- **Backend**: Ruby/Sinatra web application
- **Database**: PostgreSQL with PostGIS extension for GPS/location features
- **Queue**: Sidekiq for background jobs
- **Integration**: Home Assistant for hardware control and sensor data
- **Testing**: RSpec with VCR for API recording/playback
- **Deployment**: Self-hosted on Mac Mini at Burning Man

### Key Components

#### 1. Conversation System (`lib/modules/conversation_module.rb`)
- Central hub for processing conversations
- Session management with persistence
- Context injection from memories and current state
- Tool execution for hardware control
- Persona switching (Buddy, Jax, Lomi, Zorp)

#### 2. Home Assistant Integration
- Custom component at `config/homeassistant/custom_components/glitchcube_conversation/`
- Controls LED displays, TTS, sensors, cameras
- Webhook-based communication
- Circuit breaker pattern for resilience

#### 3. Persona System (`lib/personas/`)
- Base persona class with standard behaviors
- Character-specific implementations with unique voices/styles
- Dynamic persona switching based on context

#### 4. Memory System (`lib/services/memory/`)
- Context enrichment from past interactions
- Memory consolidation via background jobs
- Location-aware memories for Burning Man

#### 5. Tool System (`lib/tools/`)
- Display control (Awtrix LED matrix)
- Speech synthesis with multiple voices
- Camera vision analysis
- Lighting effects
- Music playback

#### 6. Entity Management System (`lib/services/system/entity_manager_service.rb`)
- Keeps Home Assistant entity list up to date
- Organizes entities by domain (light, sensor, media_player, etc.)
- Redis caching with 5-minute expiration
- Automatic refresh on entity changes
- Background job processing (`EntityDocumentationJob`)
- API endpoints for manual refresh and querying

## Testing Strategy

### VCR Configuration
- All external API calls recorded to cassettes
- Located in `spec/vcr_cassettes/`
- Auto-record new interactions in test mode
- Prevent API leakage with proper filtering

### Running Tests
```bash
bundle exec rspec                    # Run all tests
bundle exec rspec spec/integration/  # Integration tests only
VCR_RECORD=true bundle exec rspec   # Re-record cassettes
```

## Code Conventions

### Ruby Style
- 2 spaces for indentation
- Prefer composition over inheritance
- Use service objects for complex operations
- Circuit breaker pattern for external services
- Comprehensive error handling with fallbacks

### File Organization
```
lib/
  core/        # Core infrastructure (circuit breakers, clients)
  services/    # Business logic services
  modules/     # Mixins and modules
  tools/       # Hardware control tools
  personas/    # Character implementations
  routes/      # API endpoints
```

### Error Handling
- Every external call wrapped in error handling
- Fallback responses for service failures
- Detailed logging with correlation IDs
- Self-healing capabilities via ErrorHandlingLLM

## Common Commands

### Development
```bash
# Install dependencies
bundle install

# Start development server (with auto-reload + Sidekiq)
bin/dev

# Start production server (app + Sidekiq)
bin/prod

# Interactive console with app loaded (IMPORTANT: Use this for debugging/commands!)
bin/console

# Run tests with VCR options
bin/rspec                        # Normal test run
bin/rspec --vcr-none             # CI mode (no cassettes)
bin/rspec --vcr-override         # Override cassettes
bin/rspec spec/path/to/spec.rb   # Run specific test

# Run linter
bundle exec rubocop
bundle exec rubocop -a  # Auto-fix issues
```

### Rake Tasks
```bash
rake spec              # Run test suite (use bin/rspec instead)
rake run              # Run the application (use bin/dev or bin/prod)
rake console          # Interactive console (use bin/console)
rake c                # Console (alternate using IRB)
rake routes           # Show all application routes
rake health:check     # Check service health
rake logs:cleanup     # Clean up old log files
rake backup:create    # Create backup of app data
rake backup:list      # List available backups
rake deploy:push["message"]  # Deploy to production
rake deploy:quick     # Quick deploy with timestamp
rake deploy:pull      # Manual pull from GitHub (on Mac Mini)
rake deploy:check     # Check for updates (on Mac Mini)
```

### Entity Management Commands
```bash
# Update entity documentation manually
ruby scripts/update_ha_entities_doc.rb

# API endpoints for entity management
curl -X POST http://localhost:4567/api/v1/entities/refresh    # Force refresh
curl http://localhost:4567/api/v1/entities/list               # Get all entities
curl http://localhost:4567/api/v1/entities/light             # Get light entities
curl http://localhost:4567/api/v1/entities/sensor            # Get sensor entities
```

### Interactive Console Usage

The `bin/console` command gives you a Ruby console with the entire GlitchCube application loaded. This is perfect for:

**Debugging & Inspection:**
```ruby
# Check current simulation status
gps = Services::GpsTrackingService.new
location = gps.current_location
puts "#{location[:lat]}, #{location[:lng]} - #{location[:source]}"

# Check database connections
Landmark.active.count
Street.active.count
Conversation.recent.limit(3)

# Inspect Redis data
require 'redis'
redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
redis.get('current_cube_location')
```

**Manual Simulation Control:**
```ruby
# Manually trigger simulation worker
Jobs::SimulateCubeMovementWorker.perform_async

# Clear simulation and restart
redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
redis.del('current_cube_location')

# Check landmarks near current position
location = Services::GpsTrackingService.new.current_location
Landmark.within_meters(location[:lng], location[:lat], 500).limit(5).map(&:name)
```

**Cache & Service Management:**
```ruby
# Clear all caches
Services::GisCacheService.clear_cache!

# Test services
Services::HomeAssistantClient.new.test_connection
```

**Entity Management:**
```ruby
# Get all Home Assistant entities organized by domain
entities = GlitchCube::Services::EntityManagerService.get_entities_by_domain

# Force refresh entities from Home Assistant
GlitchCube::Services::EntityManagerService.refresh_entities!

# Get specific domain entities
lights = GlitchCube::Services::EntityManagerService.get_rgb_lights
motion_sensors = GlitchCube::Services::EntityManagerService.get_motion_sensors
media_players = GlitchCube::Services::EntityManagerService.get_media_players

# Get hardware capability summary
caps = GlitchCube::Services::EntityManagerService.get_hardware_capabilities
puts "RGB Lights: #{caps[:summary][:rgb_light_count]}"
puts "Motion Sensors: #{caps[:summary][:motion_sensor_count]}"
```

**Spatial Queries (PostGIS):**
```ruby
# Find nearest streets to a location
Street.nearest(lng: -119.20, lat: 40.78, limit: 3).map(&:name)

# Check if coordinates are within trash fence
Boundary.cube_within_fence?(40.78, -119.20)
```

## Common Tasks

### Adding a New Persona
1. Create persona class in `lib/personas/`
2. Inherit from `BasePersona`
3. Define voice, style, and behaviors
4. Register in `PersonaFactory`
5. Add prompt file in `prompts/`
6. Test with `spec/personas/`

### Implementing a Tool
1. Create tool class in `lib/tools/`
2. Inherit from `BaseTool`
3. Implement `execute` method
4. Register in `ToolRegistryService`
5. Add error handling and logging
6. Test with actual hardware integration

### Debugging Conversations
1. Check logs in `logs/` directory
2. Use admin interface at `/admin`
3. Review conversation history in database
4. Check Home Assistant automations
5. Verify circuit breaker states

## Environment Variables
Key variables (see `docs/ENVIRONMENT_VARIABLES.md`):
- `OPENAI_API_KEY` - LLM access
- `HOME_ASSISTANT_URL` - HA instance
- `HOME_ASSISTANT_TOKEN` - HA auth
- `DATABASE_URL` - PostgreSQL connection
- `REDIS_URL` - Sidekiq queue

## Deployment

### Mac Mini Production Setup
- Runs bare metal on Mac Mini at Burning Man camp
- Home Assistant in VMware Fusion VM
- GitHub webhook triggers deployments
- Health monitoring via Uptime Kuma
- Auto-recovery mechanisms in place

### Deployment Commands
```bash
# Deploy to production (commits, pushes to GitHub, deploys via webhook)
rake deploy:push["Your commit message"]

# Quick deploy with timestamp
rake deploy:quick

# Manual pull on Mac Mini
rake deploy:pull

# Check for updates
rake deploy:check
```

### Auto-start on Boot (Mac Mini)
```bash
# Install LaunchAgent
./scripts/install-launchagent.sh install

# Check status
./scripts/install-launchagent.sh status

# Start all services manually
./scripts/start-mac-mini.sh
```

## Hardware Context
- Awtrix LED matrix display (32x8 pixels)
- Multiple Govee LED strips
- USB speakers for TTS output  
- Temperature/humidity sensors
- Camera for vision analysis
- GPS tracking (when mobile)

## Critical Paths

### Conversation Flow
1. Wake word detection → Home Assistant automation
2. HA webhook → `/api/conversation` endpoint
3. ConversationModule processes with context
4. Tool execution for hardware control
5. Response with TTS and display updates
6. Session persistence for continuity

### Memory Injection
1. Past conversations summarized
2. Relevant memories retrieved
3. Context enriched with location/time
4. Injected into system prompt
5. Influences persona responses

## Testing Gotchas
- Always use VCR cassettes for external APIs
- Circuit breakers may need reset between tests
- Home Assistant mock responses critical
- GPS coordinates use Burning Man coordinate system
- TTS voices must match persona mappings

## Performance Considerations
- Database queries optimized with includes
- Sidekiq for async processing
- Circuit breakers prevent cascade failures
- Memory queries limited by recency/relevance
- Tool execution timeouts configured

## Security Notes
- API keys in environment variables only
- Home Assistant uses bearer token auth
- No secrets in VCR cassettes
- Input sanitization on all endpoints
- Rate limiting on public endpoints

## Debugging Commands
```bash
# Check system health
curl http://localhost:9292/api/health

# View recent conversations
psql $DATABASE_URL -c "SELECT * FROM conversations ORDER BY created_at DESC LIMIT 5;"

# Monitor Sidekiq jobs
bundle exec sidekiq

# Test specific persona
ruby scripts/testing_scripts/test_buddy_conversation.rb

# Check Home Assistant connection
ruby scripts/testing_scripts/test_ha_connection.rb
```

## Common Issues & Solutions

### "Circuit breaker open"
- Service experiencing failures
- Check logs for root cause
- Reset with `ruby reset_breaker.rb`

### VCR cassette mismatches
- Delete cassette and re-record
- Or use `VCR_RECORD=true`

### Persona not responding correctly
- Check prompt file exists
- Verify voice mapping
- Review system prompt injection

### Hardware not responding
- Verify Home Assistant connection
- Check entity states in HA
- Review automation logs

## Background Jobs

Managed by Sidekiq with Redis:
- `ConversationSummaryJob`: Summarizes conversations for memory
- `MemoryConsolidationJob`: Consolidates memories over time  
- `PersonalityMemoryJob`: Extracts personality-specific memories
- `SimulateCubeMovementWorker`: Simulates GPS movement for testing
- Configured in `config/sidekiq/sidekiq_cron.yml`

## Important Implementation Notes

### Session Management
- Sessions identified by `session_id` from Home Assistant
- Conversations persist across multiple interactions
- Context maintained through ConversationSession service
- Automatic session cleanup after inactivity

### VCR Cassette Management
- All external API calls must be recorded
- Cassettes in `spec/vcr_cassettes/`
- Use descriptive cassette names matching test context
- Filter sensitive data (API keys, tokens)
- Re-record with `VCR_RECORD=true` when APIs change

### Circuit Breaker Pattern
- Protects against cascading failures
- Configured per service (LLM, Home Assistant, Weather)
- Auto-recovery after cooldown period
- Manual reset via `ruby reset_breaker.rb`

### GPS & Location Services
- Uses Burning Man coordinate system (clock positions)
- PostGIS for spatial queries
- Location-aware memory retrieval
- GPS tracking via `GpsTrackingService`

## Development Workflow Tips

### Using AI Assistance
- Use global zen tools from your CLAUDE.md for complex debugging
- The `debug-detective` agent is particularly helpful for tough bugs
- Request code reviews when refactoring major systems
- Break complex tasks into smaller iterations

### Testing Workflow
1. Write tests first when adding new features
2. Run specific test files during development: `bundle exec rspec spec/path/to/spec.rb`
3. Use VCR cassettes to avoid hitting external APIs
4. Re-record cassettes when API responses change: `VCR_RECORD=true bundle exec rspec`
5. Keep tests green before committing

### Testing Philosophy

**What we test:**
- ✅ User-facing behavior and outcomes
- ✅ Integration between system components
- ✅ Error handling for real failure scenarios
- ✅ Business logic and domain rules

**What we DON'T test:**
- ❌ Ruby language features (JSON parsing, class variables)
- ❌ Test double implementations
- ❌ Object identity and singleton patterns
- ❌ Protected/private method implementations
- ❌ Standard library behavior

### 🔴 MANDATORY: Test-Driven Todo Management
**When using todos for development tasks, you MUST follow this tight testing loop:**

Every implementation todo item MUST be immediately followed by a corresponding test todo item. This is non-negotiable for maintaining code quality and preventing regressions.

**Required Pattern:**
```
☐ Implement feature X
☐ Write and run specs for feature X
☐ Fix bug in component Y
☐ Write and run specs for component Y fix
☐ Add validation to method Z
☐ Write and run specs for validation in method Z
☐ Run full test suite before marking feature complete
```

**Rules:**
1. **Never** have an implementation todo without a test todo
2. **Always** run the test immediately after implementation
3. **Fix** failing tests before moving to the next task
4. **Mark** both implementation and test todos complete together
5. **Run** full test suite after completing a feature group

**Example Todo List Structure:**
```
☐ Implement native tool calling handler
☐ Write and run specs for native tool calling handler
☐ Fix tool_executor.rb slice bug  
☐ Write and run specs for tool_executor fix
☐ Add response validation with fallbacks
☐ Write and run specs for response validation
☐ Add **_kwargs to tool methods
☐ Write and run specs for kwargs handling
☐ Run full integration test suite
```

This ensures every change is tested, regressions are caught immediately, and the codebase maintains high quality standards.

### Local Development Loop
1. Start the app: `bin/dev` (includes auto-reload + Sidekiq)
2. Make changes - app auto-reloads automatically
3. Test in browser/API client (http://localhost:4567)
4. Run relevant specs: `bin/rspec spec/path/to/spec.rb`
5. Check logs in `logs/` directory if issues arise
6. Commit when feature complete and tests pass

## Project Philosophy
- Embrace the chaos of Burning Man
- Fail gracefully, recover automatically
- Personality over perfection
- Delight through unexpected interactions
- Keep the art alive even when systems fail

---

Remember: This is an art project that happens to use code. The experience matters more than the implementation. When in doubt, make it weird and wonderful! 🎨✨