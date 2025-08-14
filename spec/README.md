# GlitchCube Test Suite Guide

This guide explains how to effectively test the GlitchCube conversation system with proper VCR setup and Home Assistant integration.

## Table of Contents
- [Quick Start](#quick-start)
- [VCR Recording Modes](#vcr-recording-modes)
- [Home Assistant Testing](#home-assistant-testing)
- [Conversation Testing](#conversation-testing)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Quick Start

### Running Tests
```bash
# Run all tests
bundle exec rspec

# Run specific test files
bundle exec rspec spec/modules/conversation_module_spec.rb

# Run integration tests only
bundle exec rspec spec/integration/

# Run with different VCR modes
bin/rspec --vcr-none     # CI mode (no recording)
bin/rspec --vcr-override # Force re-record everything
VCR_RECORD=true bundle exec rspec  # Record missing cassettes
```

### Test Structure
```
spec/
├── integration/          # Full integration tests with real API calls
├── modules/             # Unit tests for conversation modules
├── services/            # Service layer tests
├── support/             # Test helpers and configuration
│   ├── vcr_config.rb    # VCR security configuration
│   ├── vcr_setup.rb     # VCR initialization
│   ├── home_assistant_helpers.rb  # HA mocking helpers
│   ├── shared_contexts/ # Reusable test contexts
│   └── shared_examples/ # Reusable test behaviors
└── vcr_cassettes/       # Recorded API interactions
```

## VCR Recording Modes

VCR (Video Cassette Recorder) captures HTTP interactions for reliable, fast testing.

### 1. Development Mode (Default)
```bash
bundle exec rspec
```
- Records missing cassettes once
- Replays existing cassettes
- Best for normal development

### 2. CI Mode
```bash
bin/rspec --vcr-none
# OR set CI=true
```
- Only replays existing cassettes
- Never records new interactions
- Fails if cassette is missing
- Used in continuous integration

### 3. Override Mode
```bash
bin/rspec --vcr-override
# OR set VCR_OVERRIDE=true
```
- Re-records ALL cassettes
- Use when APIs change significantly
- **Remember to commit updated cassettes!**

### 4. Record Missing Mode
```bash
VCR_RECORD=true bundle exec rspec
```
- Records only missing cassettes
- Leaves existing cassettes unchanged
- Best for adding new tests

## Home Assistant Testing

We provide two approaches for testing Home Assistant integration:

### 1. Easy Mocking (Recommended for Unit Tests)

Use the Home Assistant helpers for quick, reliable mocking:

```ruby
RSpec.describe MyConversationFeature do
  include_context 'with_home_assistant_entities'
  
  it 'turns on the light' do
    # Mock a successful light service call
    mock_ha_service_call('light.turn_on', entity_id: 'light.cube')
    
    result = subject.call('turn on the light')
    
    expect(result[:response]).to include('light')
    expect_ha_service_call('light', 'turn_on', entity_id: 'light.cube')
  end
end
```

**Available Helpers:**
- `mock_ha_service_call(service, params)` - Mock service calls
- `mock_ha_entity_state(entity_id, state, attributes)` - Mock entity states
- `mock_ha_entities(hash)` - Mock multiple entities at once
- `stubbed_ha_client` - Fully stubbed HA client
- `expect_ha_service_call(domain, service, params)` - Verify calls were made

**Available Contexts:**
- `with_home_assistant_stubbed` - Basic stubbed client
- `with_home_assistant_entities` - Full entity set
- `with_lights_available` - Light entities preset
- `with_sensors_responding` - Sensor entities preset
- `with_media_players_available` - Media player entities
- `with_ha_service_failures` - Simulate HA failures

### 2. VCR Integration Tests (For Full Integration)

Use VCR for tests that need real Home Assistant interaction:

```ruby
RSpec.describe 'Home Assistant Integration', type: :integration do
  it 'controls lights through real HA API', vcr: true do
    result = conversation_module.call(
      message: 'turn on the cube light',
      context: { session_id: 'test-123' }
    )
    
    expect(result[:response]).to be_present
    expect(result[:error]).to be_nil
  end
end
```

**VCR will automatically:**
- Record the first run with real HA calls
- Filter sensitive data (tokens, IPs, GPS coords)
- Replay interactions on subsequent runs
- Fail fast if cassette is missing in CI

## Conversation Testing

Use shared examples for consistent conversation testing:

```ruby
RSpec.describe ConversationModule do
  include_context 'with_full_conversation_setup'
  
  let(:message) { 'Hello, how are you?' }
  let(:result) { subject.call(message: message, context: conversation_context) }
  
  # Test basic conversation response structure
  it_behaves_like 'a valid conversation response', expected_persona: 'buddy'
  
  # Test tool calling behavior
  it_behaves_like 'handles tool calls correctly'
  
  # Test Home Assistant integration
  it_behaves_like 'processes Home Assistant actions'
  
  # Test session management
  it_behaves_like 'maintains conversation session', session_id: 'test-123'
  
  # Test error handling
  it_behaves_like 'handles conversation errors gracefully'
  
  # Test persona support
  it_behaves_like 'supports persona switching'
  
  # Test visual feedback
  it_behaves_like 'provides visual feedback'
end
```

**Available Shared Examples:**
- `'a valid conversation response'` - Validates response structure
- `'handles tool calls correctly'` - Tests tool execution
- `'processes Home Assistant actions'` - Tests HA action extraction
- `'maintains conversation session'` - Tests session persistence
- `'handles conversation errors gracefully'` - Tests error handling
- `'supports persona switching'` - Tests persona behavior
- `'provides visual feedback'` - Tests LED feedback

## Troubleshooting

### Common Issues

#### 1. "No VCR cassette for external request"
```
❌ NO VCR CASSETTE FOR EXTERNAL REQUEST
Request: GET https://api.openrouter.ai/...
```

**Solutions:**
```bash
# Record the missing cassette
VCR_RECORD=true bundle exec rspec spec/path/to/failing_spec.rb

# Or add vcr: true to your test
it 'makes API calls', vcr: true do
  # test code
end
```

#### 2. "VCR tried to record in CI"
This happens when a test needs a cassette that doesn't exist.

**Solutions:**
```bash
# Record locally first
VCR_RECORD=true bundle exec rspec spec/failing_spec.rb

# Commit the new cassette
git add spec/vcr_cassettes/
git commit -m "Add VCR cassette for new test"
```

#### 3. "Home Assistant entities changed"
When HA entities change, cassettes may become stale.

**Solutions:**
```bash
# Refresh HA cassettes
rake vcr:refresh_ha

# Or delete specific cassettes and re-record
rm spec/vcr_cassettes/home_assistant/specific_test.yml
VCR_RECORD=true bundle exec rspec spec/integration/specific_test.rb
```

#### 4. "Test setup is too complex"
Too much mocking setup in each test.

**Solutions:**
```ruby
# Use shared contexts instead
include_context 'with_full_conversation_setup'

# Use shared examples for common behaviors
it_behaves_like 'a valid conversation response'
```

### VCR Management

```bash
# Validate cassettes for security issues
rake vcr:validate

# Check for old cassettes that need refreshing
rake vcr:age_report

# Clean up old backups and temp files
rake vcr:cleanup

# Full maintenance
rake vcr:maintain
```

### Debugging Tips

1. **Use descriptive test names** - VCR uses test names for cassette naming
2. **Check logs** - VCR logs requests in `logs/vcr_*.log`
3. **Inspect cassettes** - Look at YAML files to understand what's recorded
4. **Use VCR_DEBUG=true** - Shows VCR playback activity

## Best Practices

### When to Use Mocks vs VCR

**Use Home Assistant Mocks When:**
- Testing conversation logic
- Unit testing individual components
- Fast feedback loops needed
- HA entities frequently change
- Testing error scenarios

**Use VCR When:**
- Integration testing
- Testing actual API responses
- Validating request/response formats
- End-to-end conversation flows
- Testing against real HA instance

### Test Organization

```ruby
# Good: Clear test organization
RSpec.describe ConversationModule do
  describe '#call' do
    include_context 'with_full_conversation_setup'
    
    context 'with simple message' do
      let(:message) { 'Hello' }
      
      it_behaves_like 'a valid conversation response'
    end
    
    context 'with tool request', vcr: true do
      let(:message) { 'turn on the lights' }
      
      it_behaves_like 'handles tool calls correctly'
    end
  end
end
```

### VCR Security

- **Never commit secrets** - VCR filters are in place, but double-check
- **Use descriptive cassette names** - Helps with maintenance
- **Regular security audits** - Run `rake vcr:validate`
- **Filter GPS coordinates** - Already configured in VCR setup

### Performance Tips

1. **Use mocks for fast unit tests**
2. **Limit VCR to integration tests**
3. **Clean old cassettes regularly**
4. **Use shared contexts to reduce setup time**

## Configuration Files

- `spec/spec_helper.rb` - Main test configuration
- `spec/support/vcr_config.rb` - VCR security settings
- `spec/support/vcr_setup.rb` - VCR initialization
- `spec/support/home_assistant_helpers.rb` - HA mocking helpers

## Example Test Files

See these files for examples:
- `spec/modules/conversation_module_spec.rb` - Unit tests with mocks
- `spec/integration/conversation_flow_spec.rb` - Integration tests with VCR
- `spec/integration/hass_mcp_tool_spec.rb` - HA tool integration tests

---

For more help, check the inline documentation in the helper files or ask the team.