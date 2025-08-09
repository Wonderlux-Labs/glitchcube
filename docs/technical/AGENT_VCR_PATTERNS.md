# 🤖 Agent VCR Patterns - Zero-Leak Edition

> **For AI Agents**: This guide contains the ONLY VCR patterns you need to know. Stick to these patterns and never worry about API leaks again.

## 🎯 The One True Pattern

For 99% of cases, use this pattern:

```ruby
it 'your test description', vcr: true do
  # Test code that makes external API calls
end
```

**That's it.** No cassette names, no complex options, no thinking required.

## 🚫 What NOT to Use (Common Agent Mistakes)

### ❌ Don't Use These Patterns

```ruby
# DON'T: Manual VCR.use_cassette
VCR.use_cassette('some_name') do
  # test code
end

# DON'T: Complex vcr metadata
it 'test', vcr: { 
  cassette_name: 'complex_name',
  record: :new_episodes,
  match_requests_on: [:method, :uri]
} do
  # test code
end

# DON'T: VCR_OVERRIDE environment variable
# This is deprecated - use VCR_RECORD=true instead

# DON'T: Try to manually wrap individual API calls
VCR.use_cassette('api_call') do
  api_client.call_method
end
```

## ✅ Correct Patterns for All Scenarios

### New Test with External API
```ruby
it 'calls OpenRouter API for chat completion', vcr: true do
  response = LLMService.chat(['user', 'Hello'])
  expect(response).to include('content')
end
```

### Integration Test
```ruby
# Integration tests in spec/integration/ automatically get VCR
it 'full conversation flow with Home Assistant' do
  # No vcr: true needed - applied automatically
  result = ConversationModule.call(message: 'Test')
  expect(result[:response]).to be_present
end
```

### Service Test
```ruby
it 'fetches weather data from API', vcr: true do
  weather = WeatherService.update_weather_summary
  expect(weather).to include('temperature')
end
```

### Multiple API Calls in One Test
```ruby
it 'coordinates multiple API services', vcr: true do
  # All external calls in this test are automatically recorded
  weather = WeatherService.fetch_data
  response = LLMService.process_weather(weather)
  HomeAssistantClient.speak(response)
  
  expect(response).to be_present
end
```

## 🔧 Recording Commands

### Normal Development (Auto-records missing cassettes)
```bash
# Just run normally - cassettes are created automatically
bundle exec rspec spec/services/weather_service_spec.rb

# Cassettes are recorded ONCE on first run, then replayed
```

### Re-record/Update Existing Cassettes
```bash
# Use --vcr-override to re-record
bundle exec rspec --vcr-override spec/services/weather_service_spec.rb

# Or with environment variable
VCR_OVERRIDE=true bundle exec rspec spec/services/weather_service_spec.rb
```

## 🚨 Error Handling

When you see this error:
```
❌ NO VCR CASSETTE FOR EXTERNAL REQUEST
```

**Fix it in 2 steps:**
1. Add `vcr: true` to your test
2. Run `VCR_RECORD=true bundle exec rspec path/to/test`

## 🧠 Agent Decision Tree

```
Is my test making external HTTP requests?
├─ YES → Add `vcr: true` to the test
├─ NO → No VCR needed
└─ UNSURE → Add `vcr: true` anyway (safe default)

Do I need to record a cassette?
├─ Test fails with "NO VCR CASSETTE" → Run with VCR_RECORD=true
├─ Test passes → Cassette already exists
└─ New test → Will auto-record on first run

Should I use a custom cassette name?
├─ 99% of cases → NO, use auto-generated names
└─ Special case with specific naming requirements → Maybe, but ask first
```

## 📝 Template for New Tests

```ruby
RSpec.describe 'ServiceName' do
  describe '#method_that_calls_external_api' do
    it 'does something with external data', vcr: true do
      result = ServiceName.method_that_calls_external_api
      
      expect(result).to be_success
      expect(result.data).to be_present
    end

    it 'handles API errors gracefully', vcr: true do
      # Test error conditions
      expect { ServiceName.method_with_bad_data }.not_to raise_error
    end
  end
end
```

## 🎯 Key Rules for Agents

1. **Always use `vcr: true`** for tests with external APIs
2. **Never manually name cassettes** - auto-generation is better
3. **One environment variable**: Only `VCR_RECORD=true` for recording
4. **Trust the system** - don't try to optimize or customize
5. **When in doubt, add `vcr: true`** - it's a safe default

## 🚀 Migration Quick Reference

```ruby
# OLD → NEW
VCR.use_cassette('name') do     →     it 'test', vcr: true do
vcr: { cassette_name: 'x' }     →     it 'descriptive test name', vcr: true do  
VCR_OVERRIDE=true              →     VCR_RECORD=true
```

## 💡 Pro Tips

- **Descriptive test names** automatically create good cassette names
- **Integration tests** get VCR automatically - no need to add `vcr: true`
- **Recording is safe** - sensitive data is automatically filtered
- **CI never records** - only replays existing cassettes
- **Trust auto-naming** - it's consistent and organized

## 🔄 Workflow

1. Write test with `vcr: true`
2. Run test (it will fail with helpful error)
3. Record: `VCR_RECORD=true bundle exec rspec path/to/test`
4. Commit test + generated cassette
5. Done!

**Remember**: The Zero-Leak VCR system is designed to prevent the $40 API leak scenario. Stick to these simple patterns and you'll never have to worry about accidental API costs again.