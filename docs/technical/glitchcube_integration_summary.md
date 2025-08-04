# Glitch Cube Integration Summary

## Overview

The Glitch Cube project now has a working integration between:
- Ruby/Sinatra backend with Desiru framework
- OpenRouter API for AI model access
- Home Assistant for IoT device control
- Tool-based AI agents using ReAct pattern

## Key Components

### 1. Desiru Framework Integration

We're using a forked version of Desiru (https://github.com/estiens/desiru) with fixes for:
- OpenRouter adapter API call structure
- ReAct module tool description inclusion
- Class-based tool support

### 2. API Endpoints

#### `/api/v1/conversation`
- Main conversation endpoint using Desiru's ChainOfThought
- Handles context, mood, and personality switching

#### `/api/v1/tool_test`
- Demonstrates tool usage with ReAct pattern
- Uses TestTool for system information

#### `/api/v1/home_assistant`
- Integrates with Home Assistant for physical cube control
- Can check sensors, control lights, speak messages, and run scripts

### 3. Tools

#### TestTool (`lib/tools/test_tool.rb`)
- Provides system information (battery, location, sensors)
- Follows Desiru tool pattern with name, description, and call methods

#### HomeAssistantTool (`lib/tools/home_assistant_tool.rb`)
- Controls Home Assistant devices
- Actions: get_sensors, set_light, speak, run_script
- Mock responses for testing

### 4. Home Assistant Integration

The Glitch Cube can interact with Home Assistant through:
- Sensor monitoring (battery, temperature, humidity, motion, etc.)
- Light control (RGB colors, brightness, transitions)
- Text-to-speech for visitor interaction
- Script execution for complex sequences
- Camera integration for capturing moments

Mock Home Assistant endpoints are available for development/testing.

### 5. Testing

- Integration tests using VCR for API recording
- Mock Home Assistant responses in test environment
- All tests passing with proper tool execution

## Architecture Flow

```
User Request → Sinatra Endpoint → Desiru ReAct Agent
                                          ↓
                                   Tool Selection
                                          ↓
                              Tool Execution (TestTool/HAT)
                                          ↓
                                 Home Assistant API
                                          ↓
                                  Physical Device
```

## Next Steps

1. Submit PR to Desiru with our fixes
2. Implement more sophisticated Home Assistant automations
3. Add personality modules that interact with physical environment
4. Create background jobs for autonomous behaviors
5. Implement WebSocket connection for real-time HA events

## Configuration

Required environment variables:
- `OPENROUTER_API_KEY` - For AI model access
- `HOME_ASSISTANT_URL` - HA instance URL
- `HOME_ASSISTANT_TOKEN` - Long-lived access token
- `MOCK_HOME_ASSISTANT=true` - For development/testing

## Development Notes

- Use `bundle exec ruby app.rb` to run the app
- Tests use mock HA responses to avoid external dependencies
- VCR cassettes record OpenRouter API responses for fast tests
- The forked Desiru gem includes all necessary fixes