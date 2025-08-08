# Testing Scripts

This directory contains various test scripts used during development and debugging. These scripts are not part of the formal test suite but are useful for manual testing and debugging specific functionality.

## Categories

### Home Assistant Integration Tests
- `test_ha_connection.rb` - Test basic HA connectivity
- `simple_ha_test.rb` - Simple HA API test
- `test_led_direct.rb` - Direct LED control test
- `test_led_fixed.rb` - Fixed LED control test
- `test_led_simple.rb` - Simple LED test
- `test_entity_monitoring.rb` - Entity monitoring test

### AI/LLM Tests
- `test_llm_direct.rb` - Direct LLM API test
- `test_structured_output.rb` - Structured output test
- `test_raw_response.rb` - Raw response test
- `test_simple_openrouter.rb` - Simple OpenRouter test

### Conversation & Voice Tests
- `test_conversation_trace.rb` - Conversation tracing test
- `test_conversation_feedback.rb` - Conversation feedback test
- `test_tts.rb` - Text-to-speech test
- `test_tts_fix.rb` - TTS fix test
- `test_tts_console.rb` - TTS console test
- `test_voice_formats.rb` - Voice format test
- `test_voice_moods.rb` - Voice mood test

### System & Error Handling Tests
- `test_end_to_end.rb` - End-to-end system test
- `test_circuit_breaker_and_logging.rb` - Circuit breaker and logging test
- `test_self_healing.rb` - Self-healing system test
- `test_actual_problem.rb` - Specific problem debugging
- `test_monkey_patch.rb` - Monkey patch test
- `test_debug_error.rb` - Debug error test

## Usage

These scripts can be run individually for testing specific functionality:

```bash
# Run from project root
ruby scripts/testing_scripts/test_ha_connection.rb

# Or make executable and run directly
chmod +x scripts/testing_scripts/test_ha_connection.rb
./scripts/testing_scripts/test_ha_connection.rb
```

## Note

For formal testing, use the RSpec test suite in the `spec/` directory:
```bash
bundle exec rspec
```