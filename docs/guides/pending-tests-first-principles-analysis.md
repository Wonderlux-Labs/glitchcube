# Pending Tests: First Principles Analysis

## Executive Summary

Analysis of 50 pending (xit) tests reveals a mix of legacy technical debt, intentionally disabled functionality, and genuine testing gaps. From first principles, these tests fall into clear categories based on business value and technical merit.

**Key Insights:**
- 🗑️ **30% should be deleted** (legacy/broken functionality)
- 🛠️ **25% should be fixed** (core business logic)
- ⏸️ **25% should remain paused** (intentionally disabled features)  
- 🔄 **20% need architectural decisions** (unclear requirements)

## Analysis Framework

Each test evaluated on:
1. **Business Value**: Does this test critical functionality for the art installation?
2. **Technical Merit**: Is the test well-designed and maintainable?
3. **Implementation Feasibility**: Can this be reasonably fixed or should it be removed?
4. **Strategic Importance**: Does this support core user interactions at Burning Man?

---

## Category 1: 🗑️ DELETE IMMEDIATELY (15 tests)

### Broken/Deprecated Functionality Tests

**Files affected:**
- `spec/lib/home_assistant_client_awtrix_spec.rb` (7 tests)
- `spec/api/v1/request_logging_spec.rb` (6 tests)
- `spec/services/logger_service_spec.rb` (2 tests - emoji formatting)

**Analysis:**
```ruby
# spec/lib/home_assistant_client_awtrix_spec.rb
describe '#awtrix_display_text' do
  pending 'AWTRIX library changed - needs update'  # ← RED FLAG
  xit 'sends text to AWTRIX display with default parameters'
```

**Why Delete:**
- ❌ **AWTRIX tests**: Comment explicitly says "library changed - needs update"
- ❌ **Request logging tests**: All marked as "needs to be refactored to work with new SimpleLogger implementation"  
- ❌ **Logger emoji tests**: Testing emoji formatting is cosmetic, not functional behavior
- ❌ **File I/O dependent**: These tests break isolation and don't test core business logic

**Action:** Remove entirely. If AWTRIX integration matters, write new tests that focus on behavior, not internal implementation.

---

## Category 2: 🛠️ CRITICAL - FIX IMMEDIATELY (12 tests)

### Core Business Logic Tests

**Files affected:**
- `spec/services/persona_state_service_spec.rb` (3 tests)
- `spec/integration/conversation_tool_execution_spec.rb` (1 test)
- `spec/jobs/personality_memory_job_spec.rb` (2 tests)
- `spec/integration/conversation_module_integration_spec.rb` (1 test)
- `spec/lib/home_assistant_client_spec.rb` (3 tests - TTS functionality)
- `spec/lib/routes/api/conversation_spec.rb` (2 tests)

**Analysis:**

#### Persona State Service (CRITICAL)
```ruby
xit 'syncs with Home Assistant by default' do
  # TODO: HA client mocking issue - persona validation or service flow may need adjustment
xit 'persists the persona setting' do
  # FIXME: Service set_current_persona returns nil, so persistence test needs to be updated
```

**Why Critical:**
- ✅ **Core Art Experience**: Persona switching is fundamental to the cube's personality
- ✅ **User-Facing**: People at Burning Man interact with different personas (Buddy, Jax, Lomi, Zorp)
- ❌ **Service Contract Issue**: Tests reveal `set_current_persona` returns `nil` instead of the persona name

**Fix Strategy:**
1. Fix the service to return proper values
2. Update tests to match correct service contract
3. Test behavior (persona actually changes) not implementation (Redis keys)

#### TTS Integration (CRITICAL)
```ruby
xit 'successfully makes ElevenLabs TTS call to Home Assistant via script', :vcr do
xit 'uses default entity_id when not provided', :vcr do  
```

**Why Critical:**
- ✅ **Core Art Experience**: The cube MUST speak to participants
- ✅ **Hardware Integration**: TTS is how the cube expresses personality
- ❌ **Currently Broken**: These tests indicate TTS integration issues

#### Tool Execution (CRITICAL)
```ruby
xit 'executes ALL operations through LLM tool calling system' do
  # TODO: VCR cassette doesn't contain LLM response with tool calls
```

**Why Critical:**
- ✅ **Core Architecture**: Tool calling is how the cube controls its hardware
- ✅ **User Experience**: Without tool execution, cube can't light up, speak, or display
- ❌ **VCR Issue**: Missing tool calling responses in cassettes

---

## Category 3: ⏸️ KEEP PAUSED - INTENTIONALLY DISABLED (12 tests)

### Features Disabled for Valid Reasons

**Files affected:**
- `spec/lib/cube/settings_spec.rb` (3 tests)
- `spec/integration/conversation_continuation_spec.rb` (1 test)  
- `spec/integration/self_healing_integration_spec.rb` (2 tests)
- `spec/services/error_handling_llm_dry_run_spec.rb` (1 test)
- `spec/services/llm_service_retry_spec.rb` (1 test)
- `spec/lib/routes/api/conversation_integration_spec.rb` (2 tests)
- `spec/services/llm_service_structured_output_spec.rb` (1 test)
- `spec/routes/api/persona_spec.rb` (1 test)

**Analysis:**

#### Intentionally Disabled Features
```ruby
xit 'maintains separate context for simultaneous sessions (skipped - single device)', :vcr do
# ↑ CORRECT: Single device doesn't need multi-session support

xit 'analyzes a real error and proposes a fix', :vcr do  
xit 'would apply fix in YOLO mode', :vcr do
# ↑ CORRECT: Self-healing AI is too dangerous for production art installation
```

**Why Keep Paused:**
- ✅ **Intentional Design Decision**: Single device doesn't need multi-user sessions
- ✅ **Safety Concerns**: Auto-fixing code at Burning Man could break the installation
- ✅ **Circuit Breaker Logic**: These tests are inherently timing-dependent and flaky
- ✅ **Rate Limit Simulation**: External service behavior that can't be reliably tested

**Action:** Leave these disabled with clear comments explaining why.

---

## Category 4: 🔄 NEEDS ARCHITECTURAL DECISION (11 tests)

### Tests Blocked by Design Decisions

**Files affected:**
- `spec/services/gps_tracking_service_spec.rb` (1 test)
- `spec/services/logger_service_spec.rb` (4 tests - error tracking)
- `spec/lib/services/conversation/conversation_flow_manager_spec.rb` (3 tests)
- `spec/app_spec.rb` (1 test)
- `spec/integration/ha_conversation_integration_spec.rb` (1 test)
- `spec/jobs/personality_memory_job_spec.rb` (1 test)

**Analysis:**

#### GPS Service Architecture Question
```ruby
xit 'returns GPS data merged with location context' do
  # TODO: Architectural decision needed - should GPS service return actual GPS coords or simulation coords?
```

**The Question:** Should GPS service return:
- Real GPS coordinates (for actual mobile cube)
- Simulated Burning Man coordinates (for testing/demo)
- Both with a mode flag?

**Business Impact:** 
- ✅ **Location-aware memories** depend on this
- ✅ **Art installation positioning** needs GPS
- ❌ **Unclear requirements** for mobile vs stationary modes

#### Error Tracking File I/O
```ruby
xit 'tracks new errors', :vcr do
  # TODO: Error tracking tests - file I/O dependent, may need better isolation
```

**The Question:** Should error tracking:
- Write to files (current implementation)
- Use Redis/database
- Use external logging service
- Be disabled in test environment?

**Business Impact:**
- ❓ **Debugging Value**: Error tracking helps diagnose issues at Burning Man
- ❌ **Test Isolation**: File I/O breaks test independence
- ❓ **Production Value**: Unclear if file-based error tracking is actually used

---

## Recommended Actions by Priority

### Phase 1: Immediate Cleanup (Week 1)

#### 🗑️ Delete These Tests (No Discussion Needed)
```bash
# Remove broken AWTRIX tests
rm spec/lib/home_assistant_client_awtrix_spec.rb

# Remove deprecated request logging tests  
rm spec/api/v1/request_logging_spec.rb

# Remove emoji formatting tests from logger_service_spec.rb
# (Keep the structural tests, remove cosmetic ones)
```

**Rationale**: These tests explicitly say they're broken/deprecated. Removing them reduces noise and focuses effort on working functionality.

### Phase 2: Fix Critical Business Logic (Week 1-2)

#### 🛠️ Fix Persona State Service
```ruby
# Fix the actual service first
class PersonaStateService
  def set_current_persona(persona)
    normalized = persona.downcase
    redis.set(CURRENT_PERSONA_KEY, normalized)
    normalized # Return the set persona, not nil!
  end
end

# Then update tests to match fixed behavior
describe '.set_current_persona' do
  it 'returns the normalized persona name' do
    result = described_class.set_current_persona('JAX')
    expect(result).to eq('jax')
  end
  
  it 'persists the persona setting' do
    described_class.set_current_persona('jax')
    expect(described_class.get_current_persona).to eq('jax')
  end
end
```

#### 🛠️ Fix TTS Integration  
```ruby
# Re-record VCR cassettes with working TTS calls
# Focus on successful TTS execution, not internal details

describe '#speak' do
  it 'successfully sends TTS to Home Assistant', :vcr do
    result = client.speak('Hello Burning Man!', voice: :elevenlabs)
    expect(result).to be_truthy
    # Verify actual speech occurred by checking HA response
  end
end
```

#### 🛠️ Fix Tool Execution Testing
```ruby
# Create integration test with real tool calling response
# Use VCR to record LLM response that includes tool calls

describe 'Tool Execution Integration' do
  it 'executes LLM tool calls end-to-end', :vcr do
    response = post('/api/v1/conversation', {
      message: 'Make the cube red and say hello',
      session_id: 'test_session'  
    }.to_json)
    
    # Verify tools were called (check response structure)
    data = JSON.parse(response.body)
    expect(data['tool_calls_executed']).to be > 0
    expect(data['response']).to be_present
  end
end
```

### Phase 3: Architectural Decisions (Week 3)

#### 🔄 GPS Service Design Decision
**Recommendation**: Support both modes with environment flag

```ruby
class GpsTrackingService  
  def current_location
    if Cube::Settings.use_simulation_gps?
      simulation_location
    else
      real_gps_location  
    end
  end
end
```

**Test Strategy**: Test both modes separately
```ruby
describe 'GPS tracking modes' do
  context 'simulation mode' do
    before { allow(Cube::Settings).to receive(:use_simulation_gps?).and_return(true) }
    
    it 'returns simulated Burning Man coordinates' do
      location = service.current_location
      expect(location[:source]).to eq('simulation')
      expect(location).to include(:lat, :lng, :nearest_landmark)
    end
  end
  
  context 'real GPS mode' do
    before { allow(Cube::Settings).to receive(:use_simulation_gps?).and_return(false) }
    
    it 'returns actual GPS coordinates', :vcr do
      location = service.current_location  
      expect(location[:source]).to eq('gps')
      expect(location).to include(:lat, :lng)
    end
  end
end
```

#### 🔄 Error Tracking Decision
**Recommendation**: Use Redis in production, disable in tests

```ruby
class LoggerService
  def self.track_error(service, error_msg)
    return if Rails.env.test? # Skip in tests
    
    # Use Redis instead of files
    redis_key = "errors:#{service}:#{error_msg}"
    Redis.current.incr(redis_key)
  end
end
```

### Phase 4: Document Intentionally Disabled Tests (Week 4)

Add clear documentation to paused tests:

```ruby
describe 'Multi-session support' do
  xit 'maintains separate context for simultaneous sessions' do
    # INTENTIONALLY DISABLED: GlitchCube is a single-device art installation
    # Multi-session support adds complexity without benefit
    # If multiple cubes are built, this test should be re-enabled
  end
end

describe 'Self-healing system' do  
  xit 'analyzes and fixes errors automatically' do
    # INTENTIONALLY DISABLED: Auto-fixing code at Burning Man is too risky
    # Manual intervention preferred for art installation reliability
    # Could be re-enabled for development environments only
  end
end
```

---

## Summary by Test Type

| Test Type | Count | Action | Rationale |
|-----------|-------|---------|-----------|
| **Broken/Legacy** | 15 | 🗑️ Delete | Explicitly marked as broken, cosmetic, or deprecated |
| **Core Business Logic** | 12 | 🛠️ Fix | Critical for art installation functionality |
| **Intentionally Disabled** | 12 | ⏸️ Keep Paused | Valid reasons (safety, single-device, etc.) |
| **Needs Architecture Decision** | 11 | 🔄 Decide Then Act | Blocked by unclear requirements |

## Expected Impact

After implementing these recommendations:

### Immediate Benefits (Phase 1-2)
- ✅ **15 fewer failing tests** cluttering the output
- ✅ **12 critical features** properly tested and working  
- ✅ **Zero ambiguity** about what's broken vs intentionally disabled
- ✅ **Faster test suite** without file I/O and broken tests

### Long-term Benefits (Phase 3-4)  
- ✅ **Clear testing strategy** for each component
- ✅ **Architectural clarity** on GPS and error tracking
- ✅ **Maintainable test suite** that supports confident deployment
- ✅ **Documentation** of design decisions for future developers

## Testing Philosophy Reinforcement

This analysis reinforces the testing philosophy from the main analysis:

### ✅ Test What Matters for the Art Installation
- **User Experience**: Can people interact with different personas?
- **Hardware Integration**: Do lights, sound, and display work?  
- **Core Reliability**: Does the cube respond to voice commands?

### ❌ Don't Test Implementation Details
- **File formats**: Don't test log emoji formatting
- **Library internals**: Don't test AWTRIX library changes
- **Cosmetic features**: Focus on functional behavior

### 🎯 Test Strategy Alignment
- **Unit tests**: Mock everything, test logic
- **Integration tests**: Real VCR interactions, test contracts
- **End-to-end tests**: Minimal, critical user journeys only

The GlitchCube is an art installation that needs to work reliably at Burning Man. Tests should support that mission by focusing on user-facing functionality and core reliability, not implementation details or developer convenience features.