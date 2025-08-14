# Persona Switching Guide

## Overview
GlitchCube supports multiple AI personas (Buddy, Jax, Lomi, Zorp) with persistent state management through Redis and Home Assistant integration.

## Switching Personas Programmatically

### From Ruby Code
```ruby
# Get current persona
current = ConversationModule.current_persona
# => "buddy"

# Switch to a different persona
ConversationModule.switch_persona('jax')
# This automatically:
# - Updates Redis cache
# - Syncs with Home Assistant input_text.current_persona
# - Returns the new persona name

# Check it worked
ConversationModule.current_persona
# => "jax"
```

### Via API Endpoints
```bash
# Get current persona
curl http://localhost:4567/api/v1/persona

# Switch persona
curl -X POST http://localhost:4567/api/v1/persona \
  -H "Content-Type: application/json" \
  -d '{"persona": "zorp"}'

# List all available personas
curl http://localhost:4567/api/v1/personas
```

### From Home Assistant
The system automatically syncs with `input_text.current_persona` entity in Home Assistant.

When the persona changes via Ruby/API:
- The `input_text.current_persona` entity is updated
- The state is set to the persona name (lowercase)
- Attributes include display_name, timestamp, and source

## Home Assistant Automation

Create an automation to switch voice assistants when persona changes:

```yaml
automation:
  - alias: "Switch Voice Assistant on Persona Change"
    trigger:
      - platform: state
        entity_id: input_text.current_persona
    action:
      - choose:
          - conditions:
              - condition: state
                entity_id: input_text.current_persona
                state: "buddy"
            sequence:
              - service: assist_pipeline.select
                data:
                  pipeline: "Buddy Voice Pipeline"
          - conditions:
              - condition: state
                entity_id: input_text.current_persona
                state: "jax"
            sequence:
              - service: assist_pipeline.select
                data:
                  pipeline: "Jax Voice Pipeline"
          # Add more conditions for lomi and zorp
```

## Available Personas

- **buddy** - Helpful, enthusiastic assistant with broken profanity filter
- **jax** - Creative, mystical artistic personality
- **lomi** - Spiritual guide with meditation focus
- **zorp** - Alien observer studying human behavior

## Technical Details

### Redis Storage
- Key: `glitchcube:current_persona`
- TTL: 24 hours (auto-refreshes on access)
- Usage stats: `glitchcube:persona_stats:{name}`

### State Persistence
- Current persona persists across conversations
- Survives app restarts (stored in Redis)
- Falls back to 'buddy' if Redis unavailable

### Home Assistant Entity
- Entity ID: `input_text.current_persona`
- State: Current persona name (lowercase)
- Attributes:
  - `display_name`: Capitalized name
  - `last_changed_by`: Source of change
  - `timestamp`: When changed

## Testing

```ruby
# In console (bin/console)
# Test all personas
%w[buddy jax lomi zorp].each do |p|
  ConversationModule.switch_persona(p)
  puts "Switched to #{p}"
  sleep 1
end

# Verify HA sync
ha = HomeAssistantClient.new
state = ha.state('input_text.current_persona')
puts "HA shows: #{state['state']}"
```

## Troubleshooting

If personas aren't syncing with Home Assistant:
1. Check Redis is running: `redis-cli ping`
2. Verify HA connection: `HomeAssistantClient.new.test_connection`
3. Check the input_text entity exists in HA
4. Review logs: `tail -f logs/glitchcube.log`

## Usage in Conversations

When a conversation starts without specifying a persona:
1. Checks for persona in request parameters
2. Falls back to context[:persona] if provided
3. Uses PersonaStateService.get_current_persona (from Redis)
4. Defaults to 'buddy' if nothing set

This ensures consistent persona behavior across all interaction methods!