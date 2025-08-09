# 🔒 Zero-Leak VCR Guide

## Overview

The Zero-Leak VCR system provides bulletproof protection against API cost leaks while keeping VCR usage simple and agent-friendly. It eliminates the $40 API leak scenario permanently.

## 🎯 Core Principles

1. **Zero API Leaks**: All external requests MUST go through VCR
2. **Agent-Friendly**: Single pattern - `vcr: true`
3. **Automatic**: No manual cassette naming required
4. **CI-Safe**: Never records in CI, only replays

## 🚀 Quick Start

### For New Tests

```ruby
# Just add vcr: true - that's it!
it 'calls external API', vcr: true do
  # Your test code making external API calls
  response = SomeAPIClient.fetch_data
  expect(response).to be_success
end
```

### For Existing Tests

```ruby
# Convert from old patterns:
# OLD: VCR.use_cassette('my_cassette') do ... end
# NEW: Add vcr: true to the test

it 'existing test', vcr: true do
  # Test code remains the same
end
```

## 📋 VCR Recording Modes

### Development Mode (Default)
```bash
# Normal development - records missing cassettes ONCE automatically
bundle exec rspec

# Cassettes are created on first run, replayed on subsequent runs
```

### Override Mode - Re-record Everything
```bash
# Using command-line option (preferred)
bin/rspec --vcr-override

# Or using environment variable
VCR_OVERRIDE=true bundle exec rspec

# Re-records ALL cassettes, even if they exist
```

### None Mode - Emulate CI Locally
```bash
# Using command-line option (preferred)
bin/rspec --vcr-none

# Or using environment variable
VCR_NONE=true bundle exec rspec

# Acts like CI - NEVER records, only replays existing cassettes
# Useful for testing that all cassettes exist before pushing
```

### CI Mode (Automatic)
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

## 🛡️ Protection Features

### Bulletproof Request Blocking
- **Development**: Fails fast with helpful error messages
- **CI**: Never allows recording, only playback
- **Triple Protection**: VCR + WebMock + CI enforcement

### Error Messages
When a test tries to make an external request without a cassette:

```
❌ NO VCR CASSETTE FOR EXTERNAL REQUEST

Request: GET https://api.openrouter.ai/v1/models
Host: api.openrouter.ai
Test: ./spec/integration/my_spec.rb:42

CRITICAL: All external HTTP requests MUST go through VCR!

Quick fix:
1. Record the cassette: VCR_RECORD=true bundle exec rspec ./spec/integration/my_spec.rb:42
2. Commit the cassette in spec/vcr_cassettes/
3. Re-run the test

For new tests, add: vcr: true to your test
```

## 📁 Cassette Organization

Cassettes are automatically organized by:
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

## 🔄 Migration from Old VCR

### Automated Migration
```bash
# Run the migration script (coming soon)
ruby scripts/migrate_vcr_setup.rb

# Test the migration
bundle exec rspec

# Record any missing cassettes
VCR_RECORD=true bundle exec rspec
```

### Manual Migration Patterns

#### Old Pattern → New Pattern

```ruby
# OLD: Manual cassette usage
VCR.use_cassette('my_custom_name') do
  # test code
end

# NEW: Automatic cassette naming
it 'description of test', vcr: true do
  # same test code
end
```

```ruby
# OLD: Custom cassette with options
VCR.use_cassette('complex_cassette', 
  match_requests_on: [:method, :uri],
  allow_playback_repeats: true
) do
  # test code
end

# NEW: Simplified with smart defaults
it 'description of test', vcr: true do
  # same test code - options handled automatically
end
```

```ruby
# OLD: vcr: { cassette_name: 'custom' }
it 'test', vcr: { cassette_name: 'health_push/ha_available' } do
  # test code
end

# NEW: Just use vcr: true (auto-naming is better)
it 'test pushes HA health data when available', vcr: true do
  # test code - cassette auto-named from description
end
```

## 🏗️ Advanced Usage

### Custom Cassette Names (Rarely Needed)
```ruby
# Only use when you need specific naming
it 'test', vcr: { cassette_name: 'specific_name' } do
  # test code
end
```

### Integration Tests
```ruby
# Integration tests automatically get VCR
RSpec.describe 'Integration Test' do
  # No vcr: true needed - auto-applied to integration tests
  it 'calls external APIs' do
    # test code
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

### Agent Confusion
Stick to the single pattern:
- ✅ `it 'test', vcr: true do`
- ❌ `VCR.use_cassette(...)`
- ❌ Complex vcr metadata

## 📊 Monitoring

### Log Files
- `logs/vcr_unhandled_requests.log` - Tracks requests without cassettes
- `logs/vcr_summary.log` - Overall VCR usage summary
- `logs/vcr_bypass_errors.log` - Critical: requests that bypassed VCR

### Check VCR Status
```bash
# See current cassette count
find spec/vcr_cassettes -name "*.yml" | wc -l

# View recent unhandled requests
tail -f logs/vcr_unhandled_requests.log
```

## 🚨 Emergency Procedures

### If API Costs Spike
1. Check logs: `tail -f logs/vcr_bypass_errors.log`
2. Find the leaking test: look for external requests in CI logs
3. Emergency fix: Add `vcr: true` to all tests in the file
4. Record all cassettes: `VCR_RECORD=true bundle exec rspec`
5. Deploy fix immediately

### CI Suddenly Fails on VCR
1. Local developer likely forgot to commit cassettes
2. Check CI logs for missing cassette paths
3. Record locally: `VCR_RECORD=true bundle exec rspec <failed_test>`
4. Commit and push cassettes

## ✅ Best Practices

1. **Always use `vcr: true`** for tests that call external APIs
2. **Trust auto-generated cassette names** - they're consistent and organized
3. **Record locally, commit cassettes** - never record in CI
4. **Keep integration tests** - VCR makes them safe and fast
5. **Don't override VCR options** unless absolutely necessary
6. **Review cassettes before committing** - ensure no sensitive data leaked

## 🔄 Workflow Summary

1. Write test with `vcr: true`
2. Run test - it fails with helpful error
3. Record cassette: `VCR_RECORD=true bundle exec rspec`
4. Commit both test and cassette
5. CI runs test safely using recorded cassette

This workflow ensures zero API leaks while keeping development fast and simple.