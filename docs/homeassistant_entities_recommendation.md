# Home Assistant Entities Recommendation for GlitchCube

## Analysis Summary

After reviewing the codebase, I found:
- **Many defined but unused entities** - Lots of scripts and automations exist but aren't called from Ruby code
- **Duplication in weather handling** - Multiple weather sensors and storage mechanisms
- **Inconsistent naming patterns** - Mix of `glitchcube_*`, `cube_*`, and generic names
- **Overlapping functionality** - Multiple TTS scripts, deployment automations, etc.

## Issues Found

### Unused/Underutilized
- Most scripts in `scripts/` directory are not referenced in Ruby code
- Camera analysis automation exists but only motion detection is used
- Multiple deployment automations with overlapping triggers
- Recovery and health monitoring automations not integrated

### Duplications
- **Weather**: `sensor.playa_weather_api`, `sensor.weather_context_storage`, `input_text.current_weather`, `input_text.weather_*`
- **TTS**: Two separate TTS scripts (cloud and elevenlabs) with same queueing logic
- **Deployment**: `deployment.yaml`, `auto_deploy.yaml`, `github_deployment.yaml`
- **Status tracking**: Multiple sensors tracking similar state

## Recommended Consolidated Entity List

### Core Sensors (Template)
```yaml
# Single source of truth for each domain
sensor:
  - glitchcube_status:
      # Combined operational status
      state: "active|idle|error|offline"
      attributes:
        last_interaction: timestamp
        current_persona: string
        mood: string
        battery_level: number
        temperature: number
        
  - glitchcube_context:
      # Aggregated context for LLM
      state: "ready"
      attributes:
        weather_current: object
        weather_forecast: string
        location: string
        time_context: string
        recent_events: list
        
  - glitchcube_health:
      # System health monitoring
      state: "healthy|degraded|critical"
      attributes:
        api_status: string
        circuit_breakers: object
        error_rate: number
        response_time_ms: number
```

### Input Helpers (State Storage)
```yaml
input_text:
  glitchcube_host:           # API endpoint
  glitchcube_last_message:   # Last conversation
  glitchcube_current_goal:   # Active objective
  
input_boolean:
  glitchcube_active:         # Conversation active
  glitchcube_deployment:     # Deployment in progress
  glitchcube_offline_mode:   # Network issues
  
input_number:
  glitchcube_volume:         # TTS volume
  glitchcube_brightness:     # LED brightness
  glitchcube_sensitivity:    # Motion sensitivity

input_datetime:
  glitchcube_last_boot:      # System start time
  glitchcube_last_deploy:    # Last deployment
```

### Scripts (Actions)
```yaml
script:
  # Core functionality only
  glitchcube_speak:
    # Unified TTS with provider selection
    fields: [message, voice, provider, priority]
    
  glitchcube_display:
    # LED/display control
    fields: [effect, color, duration, text]
    
  glitchcube_analyze_scene:
    # Camera vision analysis
    fields: [prompt, save_image]
    
  glitchcube_emergency_stop:
    # Halt all operations
    
  glitchcube_deploy:
    # Trigger deployment
    fields: [branch, environment]
```

### Automations (Behaviors)
```yaml
automation:
  # Proactive behaviors
  - glitchcube_attention_seeking:
      # Consolidated attention-seeking based on idle time
      trigger: idle_time
      conditions: [time_of_day, last_interaction]
      
  - glitchcube_environmental_response:
      # React to motion, sound, temperature
      trigger: [motion, sound_level, temperature]
      
  - glitchcube_scheduled_behaviors:
      # Time-based actions (morning, evening, etc)
      trigger: time_pattern
      
  # System management
  - glitchcube_health_monitor:
      # Monitor and report health issues
      trigger: [error_rate, circuit_breaker, api_failure]
      
  - glitchcube_deployment_handler:
      # Single deployment automation
      trigger: [webhook, manual, schedule]
      
  # Context updates
  - glitchcube_context_refresh:
      # Update all context sensors
      trigger: time_pattern (5 min)
```

### REST Commands
```yaml
rest_command:
  glitchcube_api:
    # Single unified API endpoint
    url: "{{ glitchcube_host }}/api/{{ endpoint }}"
    method: POST
    headers: {Content-Type: application/json}
    payload: "{{ data | to_json }}"
```

## Implementation Priority

1. **Phase 1 - Core** (Immediate)
   - `sensor.glitchcube_status` 
   - `sensor.glitchcube_context`
   - `script.glitchcube_speak`
   - `automation.glitchcube_health_monitor`

2. **Phase 2 - Behaviors** (Week 1)
   - Proactive automations
   - Environmental responses
   - Display effects

3. **Phase 3 - Advanced** (Week 2+)
   - Camera analysis
   - Complex behaviors
   - Learning/adaptation

## Migration Notes

- Consolidate weather data into single `glitchcube_context` sensor
- Replace multiple TTS scripts with unified `glitchcube_speak`
- Merge deployment automations into single handler
- Use consistent `glitchcube_*` naming throughout
- Remove unused entities after confirming no dependencies

## Benefits

- **Reduced complexity**: ~70% fewer entities to manage
- **Clear purpose**: Each entity has single responsibility
- **Better performance**: Less state updates and polling
- **Easier debugging**: Clear data flow and dependencies
- **Agent-friendly**: Agents can easily understand and use standardized entities