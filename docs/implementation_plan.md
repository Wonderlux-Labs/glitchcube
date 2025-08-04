# Glitch Cube Implementation Plan

## Overview
A comprehensive plan for building an autonomous interactive art installation with Ruby/Sinatra backend, Desiru AI framework, and Home Assistant hardware integration.

## Implementation Phases

---

### Phase 1: Core Infrastructure Setup
Foundation for the entire system

1. **Application Structure**
   - Set up Ruby/Sinatra app with standard directory layout
   - Configure Desiru framework initialization
   - Module loading system setup

2. **Background Processing**
   - Install and configure Sidekiq with Redis
   - Set up job queuing infrastructure
   
3. **Error & Logging**
   - Create error handling middleware
   - Implement structured logging system
   - Add request/response logging

4. **Configuration Management**
   - Environment-based configs (dev/test/prod)
   - Secrets management
   - Feature flags

5. **Database & Persistence**
   - SQLite for development
   - PostgreSQL for production
   - Schema for conversations, state, history

6. **Health Monitoring**
   - `/health` endpoint
   - Dependency checks
   - System status reporting

---

### Phase 2: Mock Home Assistant API & Testing
Enable development without hardware

1. **MockHomeAssistant Class**
   ```
   /api/states         - Get sensor states
   /api/services       - Call HA services  
   /api/webhook        - Receive HA events
   ```

2. **Simulated Sensors**
   - Battery level (0-100%)
   - Temperature readings
   - Motion detection events
   - Light sensor data

3. **Simulated Actuators**
   - RGB light control
   - Speaker volume/playback
   - Camera snapshot simulation
   - TTS service mock

4. **Testing Infrastructure**
   - RSpec test suite
   - VCR for API recording
   - Factory fixtures for states
   - Integration test helpers

5. **Environment Toggle**
   ```ruby
   USE_MOCK_HA=true  # Development
   USE_MOCK_HA=false # Production
   ```

---

### Phase 3: Conversation Engine & Voice Output
Core interaction system

1. **Desiru Integration**
   - ConversationModule with ChainOfThought
   - Context window management
   - Session state persistence

2. **TTS Architecture**
   ```
   Option A: Server-side TTS
   [Text] → [Audio File] → [HA Speaker API]
   
   Option B: HA-side TTS (Preferred)
   [Text] → [HA TTS Service] → [Speaker]
   ```

3. **Voice Queue Manager**
   - Handle overlapping requests
   - Priority queue for urgent messages
   - Interrupt handling

4. **Personality System**
   - Load from YAML/JSON files
   - Dynamic prompt construction
   - Personality-specific responses

5. **Visual Feedback**
   - "Thinking" light patterns
   - Mood-based colors
   - Processing indicators

---

### Phase 4: Background Jobs & Scheduling
Autonomous behavior system

1. **Desiru Scheduled Jobs** (Using Desiru's built-in scheduler)
   ```
   BeaconHeartbeat
   ├── Runs every 5 minutes
   ├── Reports system status
   └── Tracks location and health
   
   DailyBackupReminder  
   ├── Runs at 3 AM daily
   ├── Sends alert to beacon
   └── Confirms system is alive
   ```

2. **Sidekiq Jobs** (Migrating to Desiru scheduler)
   ```
   ConversationHistorySynthesizer
   ├── Runs every 6 hours
   ├── Summarizes conversations
   └── Updates context
   
   PersonalitySwitcher
   ├── Scheduled personality changes
   ├── Smooth transitions
   └── Context preservation
   
   BatteryMonitor
   ├── Check every 15 minutes
   ├── Request charging at 20%
   └── Emergency mode at 10%
   
   HealthChecker
   ├── System vitals monitoring
   ├── Service availability
   └── Error rate tracking
   ```

3. **Job Configuration**
   - Desiru scheduler for periodic tasks
   - Sidekiq for one-off async jobs
   - Retry with exponential backoff
   - Dead letter queue
   - Performance monitoring

---

### Phase 5: Error Handling & Resilience
Graceful failure management

1. **Error Middleware Stack**
   ```
   Request → [Timeout Handler]
          → [Circuit Breaker]
          → [Error Catcher]
          → [Fallback Response]
          → Response
   ```

2. **Offline Entertainment Mode (No Queue System)**
   
   **OfflinePersonality Class**
   ```ruby
   class OfflinePersonality
     RESPONSES = {
       greeting: [
         "Oh hey! My internet's out but I'm still here! Want to hear my elevator music collection?",
         "Welcome to Glitch Cube offline mode! I've been practicing beatboxing.",
         "Connection lost, personality found! I've got 47 knock-knock jokes memorized."
       ],
       
       music_interludes: [
         "♪ Doo doo doo, waiting for the internet, doo doo doo ♪",
         "*humming the Jeopardy theme song badly*",
         "This is my impression of dial-up internet: EEEEEEE-AWWWWWW-EEEEEE"
       ],
       
       activities: [
         "Want to play 20 questions? I'll start: Am I connected to the internet?",
         "Let's make up new colors! I'll start: Blurple. It's blue but suspicious.",
         "I've been counting pixels. I'm up to 1,048,576."
       ]
     }
   end
   ```

   **Entertainment Features**
   - Hold music library (terrible MIDI versions)
   - Interactive word games
   - LED light shows
   - Self-aware humor about being offline
   - NO conversation queuing - just fun responses

   **Connection Monitoring**
   ```ruby
   class ConnectionMonitor
     def announce_status
       case connection_strength
       when :offline
         "Still offline! But my joke database is fully loaded!"
       when :connecting
         "Hold on... I think I see a WiFi bar! ...nope, that's just a pixel."
       when :connected
         "WE'RE BACK ONLINE! Did anything happen while I was gone?"
       end
     end
   end
   ```

3. **Service Circuit Breakers**
   - OpenRouter API
   - Home Assistant API
   - Database connections
   - Redis connections

4. **Fallback Strategies**
   - Pre-written personality responses
   - Cached conversation snippets
   - Generic acknowledgments
   - Error personality mode

---

### Phase 6: Process Management & Auto-Restart
Production reliability

1. **Systemd Services**
   ```
   glitchcube-web.service    (Puma/Sinatra)
   glitchcube-worker.service (Sidekiq)
   glitchcube-redis.service  (Redis)
   ```

2. **Health Monitoring**
   - Memory usage tracking
   - Request latency monitoring
   - Background job queue depth
   - Automatic restart triggers

3. **Startup Sequence**
   ```
   1. Check dependencies
   2. Load configuration
   3. Initialize personalities
   4. Restore conversation state
   5. Resume queued jobs
   6. Start accepting requests
   ```

4. **Deployment**
   - Zero-downtime updates
   - Rollback capability
   - Configuration hot-reload

---

### Phase 7: Hardware Control API Strategy
Deciding which Home Assistant API to use for different operations

1. **API Endpoint Decision Matrix**

   **Use HA REST API directly for:**
   ```ruby
   # Precise, programmatic control
   - Setting exact RGB values: /api/services/light/turn_on
   - Reading sensor data: /api/states/sensor.battery_level
   - Triggering specific services: /api/services/camera/snapshot
   - Getting device states: /api/states
   ```

   **Use HA Voice Assistant API for:**
   ```ruby
   # Natural language commands that leverage HA's built-in understanding
   - "Turn the lights blue"
   - "Play some music"
   - "Set mood lighting"
   - "Flash the lights three times"
   ```

2. **Implementation Example**
   ```ruby
   class HomeAssistantClient
     # Direct REST API calls for precise control
     def set_rgb(r, g, b)
       post('/api/services/light/turn_on', {
         entity_id: 'light.glitch_cube',
         rgb_color: [r, g, b]
       })
     end
     
     def get_battery_level
       get('/api/states/sensor.battery_level')['state'].to_i
     end
     
     def take_snapshot
       post('/api/services/camera/snapshot', {
         entity_id: 'camera.glitch_cube'
       })
     end
     
     # Voice Assistant API for natural commands
     def voice_command(text)
       post('/api/services/conversation/process', {
         text: text,
         agent_id: 'homeassistant'
       })
     end
     
     # Examples of voice commands
     def set_mood(mood)
       case mood
       when :happy
         voice_command("set the lights to a happy yellow color")
       when :thinking
         voice_command("pulse the lights slowly in blue")
       when :party
         voice_command("turn on disco mode")
       end
     end
   end
   ```

3. **Mood Implementations**
   - Happy: Warm colors, upbeat sounds
   - Thinking: Pulsing blue, quiet hum
   - Sad: Dim blues, minor tones
   - Charging: Green pulse, charging sound
   - Alert: Red flash, alert tone

4. **State Management**
   - Cache current hardware state
   - Batch similar commands
   - Debounce rapid changes

---

### Phase 8: Development Mode & Debugging
Interactive tools for development and testing

1. **Development Console Features**
   ```
   Commands:
     say <text>     - Simulate user speech
     hear           - Show cube response
     personality    - Show current personality
     switch <name>  - Switch personality
     state          - Show conversation state
     history        - Show conversation history
     sensors        - Show sensor readings
     lights <cmd>   - Control lights directly
     debug on/off   - Toggle debug output
     clear          - Clear conversation history
   ```

2. **Debug Information Display**
   - Chain of thought visibility
   - Model selection reasoning
   - Token usage tracking
   - API request/response logs
   - Processing time metrics
   - Hardware action queue

3. **Web Debug Interface**
   ```
   http://localhost:4567/debug
   
   Features:
   - Live conversation testing
   - Response analysis
   - State inspection
   - Export conversation logs
   - Replay functionality
   ```

4. **Development Helpers**
   ```ruby
   # Simulate multi-turn conversations
   simulate_conversation([
     { user: "Hello", expect: "greeting" },
     { user: "Tell me a joke", expect: "humor" },
     { user: "What's your battery level?", expect: "battery" }
   ])
   
   # Test personality switching
   debug_personality_switch
   
   # Monitor sensor streams
   watch_sensors(interval: 1.second)
   ```

5. **Environment Configuration**
   ```bash
   DEVELOPMENT_MODE=true
   DEBUG_LOGGING=true
   SHOW_CHAIN_OF_THOUGHT=true
   MOCK_HARDWARE=true
   ```

---

## Implementation Order

```
Week 1-2:  Phase 1 (Infrastructure) + Phase 2 (Mocking)
Week 3-4:  Phase 3 (Conversation Engine)
Week 4:    Phase 5 (Error Handling) - Build safety net first
Week 5:    Phase 4 (Background Jobs) - Now they can fail gracefully
Week 6:    Phase 6 (Process Management)
Week 7-8:  Phase 7 (Hardware Integration) + Phase 8 (Dev Mode)
```

## Key Decision Points

1. **TTS Strategy**: Start with HA-side TTS for simplicity
2. **Personality Storage**: YAML files in `config/personalities/`
3. **Hardware Control**: Voice commands for natural interactions, direct API for precise control
4. **Database**: SQLite locally, PostgreSQL in production
5. **Testing**: Mock HA API by default, real API via env flag
6. **Offline Mode**: Entertainment system, not a queue - make being offline fun

## Critical Technical Considerations

### Home Assistant API Requirements
1. **Authentication**: Long-Lived Access Token required
   ```ruby
   headers: { 'Authorization' => "Bearer #{ENV['HA_TOKEN']}" }
   ```

2. **Core Endpoints**:
   - `/api/states` - Get all entity states
   - `/api/states/<entity_id>` - Get/set specific entity state
   - `/api/services/<domain>/<service>` - Call services (lights, TTS, etc.)
   - `/api/intent/handle` - Handle voice intents (requires configuration)

3. **No Rate Limiting** but implement our own throttling for reliability

### Desiru Framework Integration
1. **Module Structure**: Use Signatures for input/output definition
   ```ruby
   class ConversationModule < Desiru::Module
     signature "user_input -> ai_response, hardware_actions"
   end
   ```

2. **Error Handling**: 
   - Use Desiru assertions with retries
   - Catch `Desiru::ModelError` for all API errors
   - Note: OpenRouter adapter has bugs with undefined error constants

3. **Reasoning Patterns**:
   - ChainOfThought for complex conversations
   - ReAct for tool-using scenarios
   - Predict for simple responses

### Memory & Resource Constraints
1. **RPi Memory Limits**: 
   - Monitor Ruby process memory (target < 150MB)
   - Redis memory limits
   - Implement conversation history pruning

2. **State Synchronization**:
   - Add command queue with deduplication
   - Implement state cache with TTL
   - Handle HA restart detection

3. **Audio Feedback Prevention**:
   - Self-deafen during TTS playback
   - Audio activity detection before speaking

### Security Boundaries
1. **API Authentication**: Both directions (Sinatra ↔ HA)
2. **Rate Limiting**: On conversation endpoints
3. **Input Sanitization**: For voice commands sent to HA

## Next Steps

1. Set up basic Sinatra application structure
2. Implement MockHomeAssistant for development
3. Create conversation endpoint with Desiru integration
4. Build development console for testing