# 🧪 GlitchCube Testing Guide

Complete guide to testing the GlitchCube conversation system, Home Assistant integrations, and VCR configuration.

## Quick Start

```bash
# Run all tests
bin/rspec

# Run with fresh cassettes (re-record external APIs)
bin/rspec --vcr-override

# Run without cassettes (CI mode)
bin/rspec --vcr-none

# Run specific test with VCR recording
VCR_RECORD=true bin/rspec spec/integration/conversation_flow_spec.rb
```

## 🎯 Three-Tier Testing Strategy

### 1. Easy Mocking (Unit Tests)
For fast, isolated unit tests that don't need real API interactions:

```ruby
RSpec.describe SomeService do
  it 'controls lights via Home Assistant' do
    # Simple one-liner mock
    ha_client = mock_ha_service_call('light.turn_on', entity_id: 'light.cube')
    
    result = subject.turn_on_lights
    
    expect(result).to be_success
  end
end
```

### 2. Shared Contexts (Integration Tests)
For integration tests that need realistic HA environments:

```ruby
RSpec.describe ConversationModule do
  include_context 'with_full_conversation_setup'
  
  it 'processes light control conversation' do
    result = subject.process_conversation('Turn on the lights', session_id: 'test')
    expect(result).to be_a_valid_conversation_response
  end
end
```

### 3. VCR Cassettes (Full Integration)
For end-to-end tests with real API recordings:

```ruby
RSpec.describe 'Full Conversation Flow', :vcr do
  it 'handles complete conversation with tool execution' do
    # Uses recorded real API interactions
    result = ConversationModule.new.process_conversation(
      'What is the temperature and turn on the cube light?',
      session_id: 'integration-test'
    )
    
    expect(result[:response]).to include('temperature')
    expect(result[:error]).to be_nil
  end
end
```

## 🔒 Zero-Leak VCR System

### Core Principles

1. **Zero API Leaks**: All external requests MUST go through VCR
2. **Agent-Friendly**: Single pattern - `vcr: true`
3. **Automatic**: No manual cassette naming required
4. **CI-Safe**: Never records in CI, only replays

### Quick Start

#### For New Tests

```ruby
# Just add vcr: true - that's it!
it 'calls external API', vcr: true do
  # Your test code making external API calls
  response = SomeAPIClient.fetch_data
  expect(response).to be_success
end
```

#### For Existing Tests

```ruby
# Convert from old patterns:
# OLD: VCR.use_cassette('my_cassette') do ... end
# NEW: Add vcr: true to the test

it 'existing test', vcr: true do
  # Test code remains the same
end
```

### VCR Recording Modes

#### Development Mode (Default)
```bash
# Normal development - records missing cassettes ONCE automatically
bundle exec rspec

# Cassettes are created on first run, replayed on subsequent runs
```

#### Override Mode - Re-record Everything
```bash
# Using command-line option (preferred)
bin/rspec --vcr-override

# Or using environment variable
VCR_OVERRIDE=true bundle exec rspec

# Re-records ALL cassettes, even if they exist
```

#### None Mode - Emulate CI Locally
```bash
# Using command-line option (preferred)
bin/rspec --vcr-none

# Or using environment variable
VCR_NONE=true bundle exec rspec

# Acts like CI - NEVER records, only replays existing cassettes
# Useful for testing that all cassettes exist before pushing
```

#### CI Mode (Automatic)
- Automatically activated when `CI=true` environment variable is set
- **NEVER** records cassettes
- Tests fail if cassettes are missing
- No configuration needed - CI environments set this automatically

### Mode Summary
| Mode | Records New | Replays Existing | Use Case |
|------|------------|------------------|----------|
| **Development** (default) | ✅ Once | ✅ | Normal development |
| **Override** (`--vcr-override`) | ✅ Always | ❌ | Update cassettes |
| **None** (`--vcr-none`) | ❌ | ✅ | Test CI behavior locally |
| **CI** (automatic) | ❌ | ✅ | Production/CI safety |

## 💬 Conversation Testing

### Basic Conversation Testing

```ruby
RSpec.describe ConversationModule do
  include_context 'with_full_conversation_setup'
  
  it 'processes a simple conversation' do
    result = subject.process_conversation('Hello!', session_id: 'test')
    
    expect(result).to be_a_valid_conversation_response(expected_persona: 'buddy')
    expect(result[:response]).to be_present
    expect(result[:error]).to be_nil
  end
end
```

### Persona Testing

#### All Personas Testing

```ruby
describe 'persona responses' do
  include_context 'with_full_conversation_setup'
  
  %w[buddy jax lomi zorp].each do |persona|
    context "#{persona} persona" do
      before do
        allow(Services::PersonaStateService).to receive(:get_current_persona)
          .and_return(persona)
      end
      
      it "responds appropriately as #{persona}" do
        result = subject.process_conversation('Tell me about yourself', session_id: 'test')
        
        expect(result[:persona]).to eq(persona)
        expect(result[:response]).to be_present
        # Could add persona-specific response checks here
      end
    end
  end
end
```

#### Buddy Persona Specific

```ruby
describe 'Buddy persona' do
  include_context 'with_full_conversation_setup'
  
  before do
    allow(Services::PersonaStateService).to receive(:get_current_persona)
      .and_return('buddy')
  end
  
  it 'provides helpful and enthusiastic responses' do
    result = subject.process_conversation('How are you doing?', session_id: 'test')
    
    expect(result[:persona]).to eq('buddy')
    expect(result[:response]).to match(/friendly|great|awesome|wonderful/i)
  end
  
  it 'offers help proactively' do
    result = subject.process_conversation("I'm feeling lost", session_id: 'test')
    
    expect(result[:response]).to match(/help|assist|support/i)
  end
end
```

### Tool Execution Testing

#### Light Control Conversations

```ruby
describe 'light control via conversation' do
  include_context 'with_full_conversation_setup'
  
  it 'turns on lights when requested' do
    # Mock the Home Assistant service call
    expect_any_instance_of(Tools::LightingControl).to receive(:call)
      .with(hash_including(action: 'turn_on'))
      .and_return({ success: true, message: 'Lights turned on' })
    
    result = subject.process_conversation('Turn on the cube lights', session_id: 'test')
    
    expect(result[:tools_used]).to include('lighting_control')
    expect(result[:response]).to match(/light|turned on/i)
  end
end
```

### Multi-turn Conversations

```ruby
describe 'multi-turn conversations' do
  include_context 'with_full_conversation_setup'
  
  let(:session_id) { 'multi-turn-test' }
  
  it 'maintains context across turns' do
    # First turn
    result1 = subject.process_conversation('Turn on the lights', session_id: session_id)
    expect(result1).to be_a_valid_conversation_response
    
    # Second turn - should remember previous context
    result2 = subject.process_conversation('Now make them blue', session_id: session_id)
    expect(result2).to be_a_valid_conversation_response
    expect(result2[:response]).to match(/blue/i)
  end
end
```

## 🏠 Home Assistant Testing

### Service Call Testing

```ruby
describe 'Home Assistant service calls' do
  let(:ha_client) { instance_double(HomeAssistantClient) }
  
  before do
    allow(HomeAssistantClient).to receive(:new).and_return(ha_client)
  end
  
  it 'calls light service with correct parameters' do
    expect(ha_client).to receive(:call_service)
      .with('light', 'turn_on', {
        entity_id: 'light.cube_light',
        brightness: 255,
        rgb_color: [255, 0, 0]
      })
      .and_return(double(success?: true))
    
    result = Tools::LightingControl.call(
      action: 'turn_on',
      entity_id: 'light.cube_light',
      brightness: 255,
      color: 'red'
    )
    
    expect(result[:success]).to be true
  end
end
```

### State Reading Testing

```ruby
describe 'sensor state reading' do
  let(:ha_client) { instance_double(HomeAssistantClient) }
  
  before do
    allow(HomeAssistantClient).to receive(:new).and_return(ha_client)
  end
  
  it 'reads temperature sensor correctly' do
    expect(ha_client).to receive(:get_state)
      .with('sensor.temperature')
      .and_return({
        'entity_id' => 'sensor.temperature',
        'state' => '22.5',
        'attributes' => {
          'unit_of_measurement' => '°C',
          'friendly_name' => 'Temperature'
        }
      })
    
    temperature = Services::SensorService.get_temperature
    expect(temperature).to eq(22.5)
  end
end
```

### Error Handling Testing

```ruby
describe 'Home Assistant error handling' do
  let(:ha_client) { instance_double(HomeAssistantClient) }
  
  before do
    allow(HomeAssistantClient).to receive(:new).and_return(ha_client)
  end
  
  it 'handles connection failures gracefully' do
    expect(ha_client).to receive(:call_service)
      .and_raise(StandardError, 'Connection failed')
    
    result = Tools::LightingControl.call(action: 'turn_on', entity_id: 'light.cube')
    
    expect(result[:success]).to be false
    expect(result[:error]).to include('Connection failed')
  end
end
```

## 📁 VCR Cassette Organization

### Directory Structure

```
spec/vcr_cassettes/
├── conversation/
│   ├── basic_conversation.yml
│   ├── tool_execution.yml
│   └── persona_switching.yml
├── home_assistant/
│   ├── service_calls/
│   │   ├── light_control.yml
│   │   └── media_player.yml
│   └── entity_states/
│       ├── sensor_readings.yml
│       └── device_status.yml
├── llm_service/
│   ├── openai_completions.yml
│   └── error_responses.yml
└── integration/
    ├── full_conversation_flow.yml
    └── multi_turn_conversation.yml
```

### Cassettes are automatically organized by:
```
spec/vcr_cassettes/
├── integration_conversation_spec/
│   ├── calls_openrouter_api.yml
│   └── handles_home_assistant_responses.yml
├── services_weather_service_spec/
│   ├── fetches_weather_data.yml
│   └── updates_home_assistant_sensor.yml
└── lib_home_assistant_client_spec/
    ├── sends_tts_command.yml
    └── controls_lights.yml
```

## 🔒 Security Configuration

### Automatic Filtering

Our VCR setup automatically filters sensitive data:

```ruby
# API Keys and Tokens
config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
config.filter_sensitive_data('<HA_TOKEN>') { ENV['HOME_ASSISTANT_TOKEN'] }

# GPS Coordinates (for privacy)
config.filter_sensitive_data('<LATITUDE>') { /("latitude":\s*)-?\d+\.\d+/ }
config.filter_sensitive_data('<LONGITUDE>') { /("longitude":\s*)-?\d+\.\d+/ }

# Network Information
config.filter_sensitive_data('<HA_HOST>') { ENV['HOME_ASSISTANT_URL'] }
config.filter_sensitive_data('<HA_IP>') { /\d+\.\d+\.\d+\.\d+/ }
```

### Manual Security Validation

```bash
# Check all cassettes for security issues
rake vcr:validate

# Generate age report for stale cassettes
rake vcr:age_report

# Full maintenance: validate, report, cleanup
rake vcr:maintain
```

## 🛠️ Key Commands

```bash
# Test Management
bin/rspec                        # Run all tests
bin/rspec spec/integration/      # Integration tests only
bin/rspec spec/lib/services/     # Service layer tests

# VCR Management  
rake vcr:validate               # Check cassettes for security issues
rake vcr:age_report             # Find old cassettes that need refresh
rake vcr:refresh_ha             # Refresh Home Assistant cassettes
rake vcr:cleanup                # Clean up test artifacts

# Development
bin/console                     # Interactive console with app loaded
bundle exec rubocop            # Run linter
bundle exec rubocop -a         # Auto-fix linting issues
```

## 🔧 Test Helpers & Shared Contexts

### Available Shared Contexts

#### `with_full_conversation_setup`
```ruby
# Sets up complete conversation environment with:
# - Mocked Home Assistant client
# - Conversation session management
# - Tool registry with all tools loaded
# - Default persona (buddy)

include_context 'with_full_conversation_setup'
```

#### `with_mock_home_assistant`
```ruby
# Basic Home Assistant mocking for unit tests
# - Mock client with basic service call responses
# - Common entity states pre-configured

include_context 'with_mock_home_assistant'
```

#### `with_vcr_cassettes`
```ruby
# VCR configuration for integration tests
# - Automatic cassette management
# - Security filtering enabled
# - CI-safe recording modes

include_context 'with_vcr_cassettes'
```

### Custom Matchers

#### `be_a_valid_conversation_response`
```ruby
# Validates conversation response structure
expect(result).to be_a_valid_conversation_response(expected_persona: 'buddy')

# Checks for:
# - Required fields: response, persona, session_id
# - No error field or error is nil
# - Response is non-empty string
# - Persona matches expected (if provided)
```

#### `have_executed_tool`
```ruby
# Validates tool execution in conversation
expect(result).to have_executed_tool('lighting_control')

# Checks that:
# - tools_used array includes the tool name
# - tool execution was successful
# - appropriate response mentions tool action
```

### Helper Methods

#### `mock_ha_service_call(service, options = {})`
```ruby
# Quick Home Assistant service call mocking
mock_ha_service_call('light.turn_on', entity_id: 'light.cube')

# Returns a mock that expects the service call with given options
```

#### `set_persona(persona_name)`
```ruby
# Set the current persona for conversation tests
set_persona('jax')

# Mocks PersonaStateService.get_current_persona
```

#### `create_conversation_session(session_id, options = {})`
```ruby
# Create a conversation session with optional context
create_conversation_session('test-session', persona: 'buddy')

# Sets up session state for multi-turn testing
```

## 🧪 Testing Patterns

### TDD Workflow

1. **Write failing test** (TDD approach)
2. **Choose appropriate tier**:
   - Mock for isolated unit tests
   - Shared context for integration tests  
   - VCR for full end-to-end tests
3. **Implement minimal code** to make test pass
4. **Refactor** while keeping tests green
5. **Run full suite** before committing

### Error Scenario Testing

```ruby
describe 'error handling' do
  include_context 'with_full_conversation_setup'
  
  it 'handles LLM service failures gracefully' do
    # Mock LLM service to raise an error
    allow_any_instance_of(Services::Llm::LLMService).to receive(:complete)
      .and_raise(StandardError, 'API unavailable')
    
    result = subject.process_conversation('Hello', session_id: 'test')
    
    expect(result[:success]).to be false
    expect(result[:error]).to include('API unavailable')
    expect(result[:fallback_response]).to be_present
  end
end
```

### Performance Testing

```ruby
describe 'performance' do
  include_context 'with_full_conversation_setup'
  
  it 'processes conversations within acceptable time limits' do
    start_time = Time.now
    
    result = subject.process_conversation('Turn on the lights', session_id: 'test')
    
    elapsed_time = Time.now - start_time
    expect(elapsed_time).to be < 5.seconds
    expect(result).to be_a_valid_conversation_response
  end
end
```

## 🔧 Troubleshooting

### Test Fails with "NO VCR CASSETTE"
1. Add `vcr: true` to your test
2. Record the cassette: `VCR_RECORD=true bundle exec rspec path/to/test`
3. Commit the new cassette file
4. Re-run the test

### CI Fails with Missing Cassettes
1. Check the error message for the exact test location
2. Record locally: `VCR_RECORD=true bundle exec rspec <location>`
3. Commit and push the cassette files

### Cassette Doesn't Match Request
The request might have changed. Re-record:
```bash
# Delete the old cassette file
rm spec/vcr_cassettes/path/to/cassette.yml

# Record fresh
VCR_RECORD=true bundle exec rspec path/to/test
```

### Slow Tests
1. Check if you're using VCR for unit tests (prefer mocking)
2. Ensure cassettes exist (avoid re-recording in development)
3. Use appropriate shared contexts vs full setup

### Mock Issues
1. Use `allow` instead of `expect` for setup
2. Use `expect` for assertions you want to verify
3. Reset mocks between tests using `before` blocks

## ✅ Best Practices

1. **Always use `vcr: true`** for tests that call external APIs
2. **Trust auto-generated cassette names** - they're consistent and organized
3. **Record locally, commit cassettes** - never record in CI
4. **Keep integration tests** - VCR makes them safe and fast
5. **Don't override VCR options** unless absolutely necessary
6. **Review cassettes before committing** - ensure no sensitive data leaked
7. **Use appropriate test tier** - Don't use VCR for simple unit tests
8. **Test error scenarios** - Include failure mode testing
9. **Keep tests focused** - One concept per test
10. **Use descriptive test names** - They become cassette names

## 🔄 Workflow Summary

1. Write test with `vcr: true`
2. Run test - it fails with helpful error
3. Record cassette: `VCR_RECORD=true bundle exec rspec`
4. Commit both test and cassette
5. CI runs test safely using recorded cassette

This workflow ensures zero API leaks while keeping development fast and simple.