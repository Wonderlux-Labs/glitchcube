# Glitch Cube TODO

## Interactive Functionality Roadmap (CURRENT FOCUS)

### Phase 1: Core Conversation Flow (2-3 weeks - IMMEDIATE PRIORITY)

#### CRITICAL: Multi-Turn Conversation Sessions
- [ ] **ConversationSession Management System**
  - [ ] Replace instance variables in ConversationModule with Redis-based session storage
  - [ ] Implement `ConversationSession` class with proper state management
  - [ ] Add session persistence, retrieval, and cleanup logic
  - [ ] Prevent memory leaks from current instance variable approach

- [ ] **Missing API Endpoints for Conversation Flow**
  - [ ] `POST /api/v1/conversation/start` - Initialize conversations with session ID
  - [ ] `POST /api/v1/conversation/continue` - Multi-turn conversation support
  - [ ] `POST /api/v1/conversation/end` - Graceful conversation endings
  - [ ] Update existing `/conversation` endpoint to use session management

- [ ] **Motion Detection → Conversation Integration**  
  - [ ] Home Assistant automation to call conversation start endpoint
  - [ ] Connect motion sensors to proactive conversation initiation
  - [ ] Implement automatic voice assistant reactivation after responses
  - [ ] Test motion-triggered conversation flow end-to-end

### Phase 2: Hardware Expression Enhancement (1-2 weeks)

#### HIGH: Coordinated Hardware Responses
- [ ] **LightingOrchestrator Service**
  - [ ] `express_mood(mood, intensity)` - mood-based lighting patterns
  - [ ] `synchronized_response(text, mood, context)` - combine speech + lighting + movement
  - [ ] Personality-driven RGB lighting behaviors
  - [ ] Environmental response visual expressions

- [ ] **Multi-Modal Hardware Expression**
  - [ ] Coordinate TTS speech with RGB lighting changes
  - [ ] Add curiosity-driven visual behaviors
  - [ ] Implement attention-getting lighting patterns
  - [ ] Sync hardware responses with conversation emotional tone

### Phase 3: Relationship Building & Memory Integration (1-2 weeks)

#### HIGH: Memory System Integration with Live Conversations
- [ ] **Active Memory Retrieval**
  - [ ] Integrate existing memory consolidation with live conversation context
  - [ ] Retrieve conversation history for returning visitors
  - [ ] Add visitor pattern recognition and greeting personalization
  - [ ] Implement progressive relationship development logic

- [ ] **Personalized Interaction Patterns**
  - [ ] Customized greetings based on conversation history
  - [ ] Track conversation topic preferences over time
  - [ ] Emotional state tracking across multiple sessions
  - [ ] Recognition of frequent vs new visitors

### Phase 4: Autonomous Art Installation Behaviors (1 week)

#### MEDIUM: Proactive Interaction System
- [ ] **Environmental Response Triggers**
  - [ ] Scheduled artistic moments (hourly curiosity bursts, daily mood shifts)
  - [ ] Time-based personality changes (morning optimism, evening contemplation)
  - [ ] Weather-responsive behaviors using weather service
  - [ ] Audience size detection and response adaptation

- [ ] **Autonomous Conversation Initiation**
  - [ ] Curiosity-driven conversation starters when motion detected
  - [ ] Attention-seeking behaviors when ignored for extended periods
  - [ ] Environmental commentary and artistic observations
  - [ ] Proactive relationship building with repeat visitors

## Code Architecture Improvements (Supporting Interactive Features)

### MEDIUM: Architecture Refactoring
- [ ] **Decouple ConversationModule Dependencies**
  - [ ] Remove direct HomeAssistant client coupling
  - [ ] Extract logging concerns to service layer
  - [ ] Simplify conversation flow for maintainability
  - [ ] Add proper dependency injection for testing

### LOW: Performance & Responsiveness  
- [ ] **Async Processing for Conversations**
  - [ ] Non-blocking AI API calls for more responsive interactions
  - [ ] Background processing for memory consolidation during active conversations
  - [ ] Connection pooling for external API calls
  - [ ] Optimize conversation response times

## Success Metrics for Interactive Experience

The Glitch Cube will be a successful interactive art installation when:
1. ✅ **Multi-turn conversations**: Visitors can engage in natural flowing dialogue
2. ✅ **Proactive engagement**: Cube initiates interactions based on motion/environment  
3. ✅ **Hardware expression**: RGB lighting and audio dynamically respond to conversation mood
4. ✅ **Relationship building**: System demonstrates memory and evolving interactions with visitors
5. ✅ **Autonomous behaviors**: Artistic moments beyond pure reactivity to human input

## Home Assistant Integration Status ✅

**Status**: ✅ Connected to Home Assistant at http://glitchcube.local:8123 (192 entities available)

### Entity Configuration Assessment:
Based on the live entity scan (see `docs/home_assistant_entities.md`):

#### ✅ Available and Ready:
- ✅ **weather.openweathermap** & **weather.forecast_home** - Weather data available
- ✅ **input_text.current_weather** - Weather summary storage (working)
- ✅ **media_player.tablet** & **media_player.tablet_2** - Audio output available
- ✅ **camera.tablet** - Camera for visual input
- ✅ **Motion detection infrastructure** - `input_boolean.motion_detected`, `input_boolean.human_detected`

#### ❌ Missing Entities (Need Configuration):
- ❌ **sensor.battery_level** - Battery monitoring (needs hardware sensor)
- ❌ **sensor.temperature/outdoor_temperature/outdoor_humidity** - Environmental sensors (needs hardware)
- ❌ **binary_sensor.motion** - Direct motion sensor (using input_boolean instead)
- ❌ **Light entities** - No RGB lighting configured yet
- ❌ **media_player.glitch_cube_speaker** - Needs renaming or alias

#### 🎯 Immediate Integration Opportunities:
- ✅ **TTS Integration**: Use existing `media_player.tablet` for speech output
- ✅ **Motion Detection**: Use `input_boolean.motion_detected` and automations  
- ✅ **Weather System**: Already integrated and working
- ✅ **Camera Integration**: Use `camera.tablet` for visitor recognition
- 🔧 **System Monitoring**: Rich sensor data available (CPU, memory, temperature)

### Ready for Interactive Development:
Since HA is connected and has usable entities, we can proceed with interactive features using available hardware while gradually adding missing sensors.

---

## Critical Missing Tests (High Priority)

### 1. Configuration System Tests
- [ ] Test `GlitchCube::Config.validate!` method
- [ ] Test required vs optional environment variables
- [ ] Test production configuration validation
- [ ] Test `redis_connection` and `persistence_enabled?` helpers
- [ ] Test configuration errors in different environments

### 2. Infrastructure Components (0% Coverage)
- [ ] **BeaconService** tests - critical for gallery monitoring
  - [ ] Test heartbeat sending
  - [ ] Test alert sending
  - [ ] Test error handling and retries
- [ ] **BeaconHeartbeatJob** tests - essential for 24/7 operations
  - [ ] Test successful heartbeat job execution
  - [ ] Test job failure scenarios
  - [ ] Test job result storage
- [ ] **BeaconAlertJob** tests
  - [ ] Test alert job execution
  - [ ] Test different alert levels
- [ ] Redis connection failure/recovery scenarios
- [ ] Sidekiq queue processing error handling

### 3. Art Installation Scenarios
- [ ] Power loss/restart recovery testing
- [ ] Network connectivity interruption during conversations
- [ ] Resource exhaustion on Raspberry Pi (memory/CPU/storage)
- [ ] Multiple concurrent visitors/conversations
- [ ] Temperature monitoring for 24/7 operation
- [ ] SD card wear considerations

### 4. System Integration
- [ ] End-to-end flow with all services (HA + AI + Background jobs)
- [ ] Graceful degradation when services are unavailable
- [ ] Long-running conversation memory management
- [ ] Docker environment-specific behaviors

## High Priority Tests

### Error Recovery & Resilience
- [ ] Test what happens when Redis/Sidekiq goes down
- [ ] Test OpenRouter API failures and fallbacks
- [ ] Test Home Assistant becomes unavailable mid-conversation
- [ ] Test database connection failures
- [ ] Test disk space exhaustion scenarios

### Performance & Load Testing
- [ ] Test handling multiple concurrent conversations
- [ ] Test memory usage under load
- [ ] Test conversation cleanup and memory management
- [ ] Test Raspberry Pi resource constraints

### Missing Service Tests
- [ ] **ContextRetrievalService** unit tests (has integration tests)
- [ ] **ConversationSummarizer** unit tests (has integration tests)
- [ ] **SystemPromptService** edge case coverage

## Medium Priority Tests

### Network & Connectivity
- [ ] Test offline/poor connectivity scenarios
- [ ] Test network interruption during API calls
- [ ] Test timeout handling for external services

### Configuration & Environment
- [ ] Test environment variable validation
- [ ] Test different RACK_ENV configurations
- [ ] Test Docker-specific scenarios
- [ ] Test required vs optional config validation

### Integration Scenarios
- [ ] Test multi-user simultaneous conversations
- [ ] Test conversation context switching
- [ ] Test service dependency chains

## Low Priority Tests

### Docker & Deployment
- [ ] Test Docker environment-specific behaviors
- [ ] Test container health checks
- [ ] Test volume mounting in different environments

### Monitoring & Alerting
- [ ] Test health endpoint monitoring
- [ ] Test log aggregation
- [ ] Test disk space monitoring
- [ ] Test temperature monitoring alerts

### Optimization
- [ ] Test image cleanup processes
- [ ] Test log rotation effectiveness
- [ ] Test backup/restore procedures

## Test Infrastructure Improvements

### Current Strengths
- ✅ Excellent VCR setup for API testing
- ✅ Good separation of unit vs integration tests
- ✅ Proper mock/stub usage for external services
- ✅ Clean test data management and cleanup
- ✅ SimpleCov for coverage tracking

### Areas for Enhancement
- [ ] Add performance benchmarking
- [ ] Add memory usage tracking in tests
- [ ] Add flaky test detection
- [ ] Add test parallelization for faster CI

## Notes

**Priority Focus**: Infrastructure components (BeaconService, Configuration validation) are critical for deployment safety and 24/7 gallery operation.

**Art Installation Context**: Tests should consider the unique requirements of an autonomous art installation running 24/7 in gallery environments with potential power issues, network instability, and resource constraints.