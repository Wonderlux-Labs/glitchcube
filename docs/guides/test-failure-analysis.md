# Test Failure Analysis and Remediation Guide

## Executive Summary

The GlitchCube test suite currently shows **1 active failure** and **88 pending (skipped) tests**. The test suite is largely healthy, but there are systematic issues that need addressing to improve test reliability and maintainability.

## Current Status

- ✅ **734 passing tests** (99.86% pass rate)
- ❌ **1 failing test** (0.14% failure rate)  
- ⏭️ **88 pending tests** (10.7% of total tests)

## Root Cause Analysis

### The One Failing Test

**Test**: `Simple Session Management - Phase 3.5 ends conversation when end_conversation is true`  
**File**: `spec/integration/simple_session_management_spec.rb:146`

**Issue**: Brittle expectation based on LLM response content
- **Expected**: Response containing goodbye/farewell language
- **Actual**: "What a fantastic fucking question! Let's figure this out together!"

**Root Cause**: Test assumes specific LLM behavior for "Goodbye" input, but the recorded VCR cassette contains a different response.

### Categorization of Pending Tests

#### Category 1: Home Assistant Integration Issues (30+ tests)
**Pattern**: Tests requiring live HA connection or proper HA mocking

**Examples**:
```ruby
# TODO: Requires working Home Assistant instance
xit 'speaks using local TTS provider' do
  # TODO: HA client mocking issue - persona validation or service flow may need adjustment  
xit 'syncs with Home Assistant by default' do
```

**Root Causes**:
- Incomplete HA client mocking
- Complex HA entity state dependencies
- Authentication token handling in tests
- VCR cassettes with 401 Unauthorized responses

#### Category 2: VCR/External Service Issues (25+ tests)
**Pattern**: Tests depending on external API behavior that's hard to record

**Examples**:
```ruby
# TODO: VCR cassette doesn't contain LLM response with tool calls
xit 'executes ALL operations through LLM tool calling system' do
  # TODO: Investigate VCR recording for STDIO subprocess interactions
xit 'analyzes a real error and proposes a fix', :vcr do
```

**Root Causes**:
- LLM responses vary between recordings
- Complex subprocess interactions (MCP connectors)
- Circuit breaker timing dependencies
- Rate limit simulation challenges

#### Category 3: Service Mocking Complexity (20+ tests)
**Pattern**: Tests with over-complex mocking that breaks easily

**Examples**:
```ruby
# TODO: Fix mock setup for error handler - needs proper double with handle_error method
xit 'handles service failures gracefully' do
  # FIXME: Service set_current_persona returns nil, so persistence test needs to be updated
xit 'persists the persona setting' do
```

**Root Causes**:
- Service interfaces changed but mocks didn't update
- Deep dependency injection making mocking complex
- Return value expectations not matching actual service behavior

#### Category 4: File I/O and Redis Dependencies (15+ tests)
**Pattern**: Tests depending on file system or Redis state

**Examples**:
```ruby
# TODO: Error tracking tests - file I/O dependent, may need better isolation
xit 'tracks new errors', :vcr do
  # TODO: Redis key matching test - regex pattern may need adjustment
xit 'marks error as analyzed in Redis' do
```

**Root Causes**:
- Tests not properly isolated from file system
- Redis key expectations too brittle
- File-based logging tests interfering with each other

#### Category 5: Timing and Flaky Tests (8+ tests)
**Pattern**: Tests with inherent timing dependencies

**Examples**:
```ruby
# TODO: Circuit breaker timing tests are inherently flaky - timing-dependent behavior
xit 'opens circuit breaker after consecutive failures' do
  # TODO: Flaky test - depends on simulating rate limit errors which may not be consistent
xit 'retries on rate limit errors', :vcr do
```

**Root Causes**:
- Circuit breaker recovery timeouts
- Race conditions in async operations
- External service timing variations

## Remediation Strategies

### 1. Fix the Active Failure (HIGH PRIORITY)

**Strategy**: Test behavior, not content
```ruby
# Instead of testing exact response content:
expect(response_data['data']['response']).to match(/(?i)(goodbye|bye|farewell)/)

# Test the actual behavior:
expect(response_data['data']['end_conversation']).to be_truthy
expect(response_data['data']['response']).to be_present
# Optionally check conversation state was properly ended
```

**Implementation**:
- Re-record VCR cassette with conversation ending behavior
- Focus on `end_conversation` flag rather than response content
- Add separate unit test for farewell detection logic if needed

### 2. Home Assistant Test Improvements (MEDIUM PRIORITY)

**Strategy**: Comprehensive HA mocking framework

```ruby
# Create shared test helper in spec/support/home_assistant_helpers.rb
module HomeAssistantTestHelpers
  def mock_ha_full_setup
    mock_ha_connection
    mock_ha_entities
    mock_ha_service_calls
  end

  def mock_ha_entities(entities = {})
    default_entities = {
      'light.cube_primary' => { 'state' => 'on', 'attributes' => {} },
      'sensor.glitchcube_context' => { 'state' => 'active', 'attributes' => {} },
      'media_player.square_voice' => { 'state' => 'idle', 'attributes' => {} }
    }
    mock_client.stub_responses(:get_states, default_entities.merge(entities))
  end
end
```

**Benefits**:
- Consistent HA mocking across all tests
- Easy to update when HA interface changes
- Realistic entity responses without live connection

### 3. VCR Strategy Overhaul (MEDIUM PRIORITY)

**Strategy**: Smart cassette management and better isolation

**A. LLM Response Normalization**:
```ruby
# In VCR configuration
VCR.configure do |config|
  config.define_cassette_serializer :smart_llm do |file|
    {
      # Normalize varying LLM responses to focus on structure
      normalize_llm_responses: true,
      filter_sensitive_data: ['api_key', 'tokens'],
      match_requests_on: [:method, :uri_without_params]
    }
  end
end
```

**B. Separate Unit vs Integration Tests**:
```ruby
# Unit tests: Mock all external dependencies
describe 'ConversationFlowManager (unit)' do
  let(:mock_llm) { instance_double(Services::LLMService) }
  let(:mock_ha) { instance_double(Core::HomeAssistantClient) }
  
  before do
    allow(Services::LLMService).to receive(:new).and_return(mock_llm)
    allow(Core::HomeAssistantClient).to receive(:new).and_return(mock_ha)
  end
end

# Integration tests: Use VCR with stable cassettes
describe 'Conversation Integration', :vcr do
  # Test real behavior with recorded responses
end
```

### 4. Service Mock Simplification (HIGH PRIORITY)

**Strategy**: Replace complex mocks with test doubles and factories

**Current Problem**:
```ruby
# Overly complex mocking
allow(Services::PersonaStateService).to receive(:set_current_persona)
  .with('jax').and_return(nil) # But service actually returns 'jax'!
```

**Solution**:
```ruby
# Test doubles that match real service contracts
class TestPersonaStateService
  def initialize(initial_persona = 'buddy')
    @current_persona = initial_persona
  end
  
  def set_current_persona(persona)
    @current_persona = persona.downcase
    @current_persona # Return the set persona, not nil
  end
  
  def get_current_persona
    @current_persona
  end
end

# In test setup
let(:persona_service) { TestPersonaStateService.new }
before { allow(Services::PersonaStateService).to receive(:new).and_return(persona_service) }
```

### 5. File I/O and Redis Test Isolation (MEDIUM PRIORITY)

**Strategy**: In-memory alternatives and proper cleanup

```ruby
# Redis isolation
RSpec.configure do |config|
  config.around(:each, :redis) do |example|
    Redis.new.flushdb # Clean slate for each test
    example.run
    Redis.new.flushdb # Clean up after
  end
end

# File I/O isolation  
RSpec.configure do |config|
  config.around(:each, :file_io) do |example|
    Dir.mktmpdir do |temp_dir|
      allow(Services::Logging::SimpleLogger).to receive(:log_directory).and_return(temp_dir)
      example.run
    end
  end
end
```

### 6. Timing Test Stabilization (LOW PRIORITY)

**Strategy**: Make timing explicit and controllable

```ruby
# Instead of real timeouts:
allow(circuit_breaker).to receive(:recovery_timeout).and_return(0.1) # Fast for tests

# Use Timecop for time-dependent tests:
it 'opens circuit breaker after timeout' do
  Timecop.freeze do
    # Initial failures
    3.times { circuit_breaker.call { raise 'error' } }
    
    # Fast forward past recovery timeout
    Timecop.travel(circuit_breaker.recovery_timeout + 1) do
      expect(circuit_breaker.state).to eq(:half_open)
    end
  end
end
```

## Implementation Priority

### Phase 1: Critical Fixes (Week 1)
1. ✅ Fix the single failing test by focusing on behavior over content
2. ✅ Create shared HA test helpers for consistent mocking
3. ✅ Implement TestPersonaStateService to fix persona tests

### Phase 2: VCR Improvements (Week 2)  
1. ✅ Audit and re-record problematic VCR cassettes
2. ✅ Implement LLM response normalization
3. ✅ Separate unit tests (mocked) from integration tests (VCR)

### Phase 3: Test Infrastructure (Week 3)
1. ✅ Add Redis and file I/O isolation helpers  
2. ✅ Create test factories for common service configurations
3. ✅ Implement timing test stabilization with Timecop

### Phase 4: Enable Remaining Tests (Week 4)
1. ✅ Systematically un-skip tests using new infrastructure
2. ✅ Monitor for new flaky tests and address root causes
3. ✅ Document testing patterns for future development

## Expected Outcomes

After implementation:
- ✅ **0 failing tests** (target: 100% pass rate)
- ✅ **<20 pending tests** (target: <3% pending rate)  
- ✅ **Stable CI/CD** with consistent test results
- ✅ **Faster test suite** through better isolation
- ✅ **Maintainable tests** that don't break on service changes

## Testing Philosophy Going Forward

### Test What Matters
- ✅ **Behavior over implementation**: Test outcomes, not internal method calls
- ✅ **User-facing functionality**: Test API contracts and user interactions
- ✅ **Error conditions**: Ensure graceful failure handling
- ❌ **Don't test**: Language features, library behavior, implementation details

### Keep Tests Fast and Reliable
- ✅ **Unit tests**: Fast, isolated, mock external dependencies
- ✅ **Integration tests**: Test real interactions with VCR
- ✅ **End-to-end tests**: Minimal, focus on critical user journeys
- ✅ **Avoid**: Flaky timing, external service dependencies, file system state

### Maintenance Strategy
- ✅ **Regular VCR hygiene**: Update cassettes when APIs change
- ✅ **Mock contract testing**: Ensure mocks match real service behavior  
- ✅ **Test isolation**: Each test should run independently
- ✅ **Clear test intent**: Test names and structure should be obvious

This systematic approach will transform the test suite from brittle and unreliable to robust and maintainable, supporting confident development and deployment of the GlitchCube art installation.