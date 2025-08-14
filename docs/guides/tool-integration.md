# Tool System & Hardware Integration Guide

The Glitch Cube uses a standardized tool system that allows AI personas to interact with hardware, services, and external APIs. All tools inherit from `BaseTool` and follow consistent patterns for parameters, validation, and execution.

## Architecture Overview

```
┌─────────────────────┐    ┌──────────────────────┐    ┌─────────────────────┐
│   Conversation      │────│   ToolRegistryService │────│   Individual Tools  │
│   Module            │    │                      │    │   (inherit BaseTool)│
└─────────────────────┘    └──────────────────────┘    └─────────────────────┘
          │                           │                           │
          │                           │                           │
          ▼                           ▼                           ▼
┌─────────────────────┐    ┌──────────────────────┐    ┌─────────────────────┐
│  Character Service  │    │  Tool Executor       │    │  Home Assistant     │
│  (persona configs)  │    │  (parallel exec)     │    │  Client             │
└─────────────────────┘    └──────────────────────┘    └─────────────────────┘
```

## Tool Structure

### Base Tool (`lib/tools/base_tool.rb`)

All tools inherit from `BaseTool` which provides:

- **Validation**: Parameter validation with `validate_required_params`
- **JSON Parsing**: Safe JSON parameter parsing with `parse_json_params`
- **HA Integration**: Home Assistant client access via `ha_client`
- **Error Handling**: Consistent error formatting with `format_response`
- **Mocking**: Test support with `MockHomeAssistantClient`

### Required Methods

Each tool must implement:

```ruby
class MyTool < BaseTool
  def self.name
    'my_tool_name'  # Tool identifier for function calling
  end

  def self.description
    'What this tool does. Args: param1 (type), param2 (type)'
  end

  def self.call(**args)
    # Implementation here
  end
end
```

### Optional Methods

```ruby
def self.parameters
  {
    'param_name' => {
      type: 'string',
      description: 'What this parameter does',
      enum: %w[option1 option2]  # Optional: restrict to specific values
    }
  }
end

def self.required_parameters
  %w[param1 param2]
end

def self.category
  'hardware_control'  # Categories: hardware_control, system_integration, etc.
end

def self.examples
  ['Example usage descriptions']
end
```

## Parameter Signatures & Validation

### Parameter Types

Tools support standard OpenAI function calling parameter types:

```ruby
{
  'string_param' => { type: 'string', description: 'Text input' },
  'number_param' => { type: 'number', description: 'Numeric input' },
  'boolean_param' => { type: 'boolean', description: 'True/false input' },
  'enum_param' => { 
    type: 'string', 
    enum: %w[option1 option2],
    description: 'Choose from options'
  },
  'object_param' => {
    type: 'object',
    description: 'JSON object with nested data'
  }
}
```

### Validation Patterns

```ruby
def self.call(action:, params: '{}')
  # 1. Validate required parameters
  validate_required_params({ 'action' => action }, ['action'])
  
  # 2. Parse JSON parameters safely
  params = parse_json_params(params)
  
  # 3. Validate specific values
  unless %w[valid_action1 valid_action2].include?(action)
    return format_response(false, "Invalid action: #{action}")
  end
  
  # 4. Implementation...
end
```

### Error Handling

Use `BaseTool` helpers for consistent responses:

```ruby
# Success
format_response(true, "Action completed successfully", optional_data)

# Failure  
format_response(false, "Error occurred: #{error_message}")

# Home Assistant service calls
call_ha_service('light', 'turn_on', { entity_id: 'light.cube' })
# Returns: "✅ Service light.turn_on executed successfully"

# State retrieval
get_ha_state('sensor.temperature')
# Returns: { entity_id: '...', state: '72', attributes: {...} }
```

## Available Tools

### Hardware Control

- **`lighting_control`**: RGB lighting, scenes, effects
- **`camera_control`**: Image capture, analysis, streaming  
- **`display_control`**: AWTRIX display text and graphics

### System Integration

- **`home_assistant`**: General HA service calls and state queries
- **`home_assistant_parallel`**: Batch operations with parallel execution
- **`music_control`**: Music Assistant integration, playback control

### Utility

- **`test_tool`**: Development testing and debugging
- **`error_handling`**: Error analysis and recovery suggestions

## Tool Registration & Discovery

### Automatic Discovery

The `ToolRegistryService` automatically discovers tools in `/lib/tools/`:

```ruby
# Get all available tools
all_tools = Services::ToolRegistryService.discover_tools

# Get OpenAI function schemas
functions = Services::ToolRegistryService.get_openai_functions(['tool1', 'tool2'])

# Get persona-specific tools
buddy_tools = Services::ToolRegistryService.get_tools_for_character('buddy')
```

### Persona-Specific Tools

Tools are assigned to personas in `CharacterService`:

```ruby
buddy: {
  name: 'BUDDY',
  tools: %w[error_handling test_tool lighting_control music_control home_assistant display_control]
}
```

# Hardware Integration

## AWTRIX LED Display

### Overview
32x8 RGB LED matrix display for visual feedback and information display.

### Integration
- Controlled via Home Assistant scripts
- Service: `script.awtrix_send_custom_app`
- Tools: `display_tool.rb`, `lighting_tool.rb`

### Ruby API (HomeAssistantClient)

```ruby
# Initialize the client
ha_client = HomeAssistantClient.new

# Display text on AWTRIX
ha_client.awtrix_display_text("Hello World!")

# Display with custom parameters
ha_client.awtrix_display_text(
  "Rainbow Text",
  app_name: 'myapp',
  color: [255, 0, 0],    # Red text
  duration: 10,          # Show for 10 seconds
  rainbow: true,         # Rainbow effect
  icon: '1234'          # Icon ID
)

# Send a notification (stays until dismissed)
ha_client.awtrix_notify(
  "Alert!",
  color: [255, 0, 0],    # Red text
  hold: true,            # Keep until dismissed
  sound: 'alarm',        # Play alarm sound
  icon: '5678'          # Icon ID
)

# Clear the display
ha_client.awtrix_clear_display

# Set mood lighting
ha_client.awtrix_mood_light(
  [255, 0, 255],        # Purple color
  brightness: 50        # 50% brightness
)
```

### Home Assistant Scripts

#### Display Custom App
```yaml
service: script.awtrix_send_custom_app
data:
  app_name: "glitchcube"
  text: "Hello World"
  color: [255, 255, 255]
  duration: 5
  rainbow: false
  icon: "1234"  # Optional
```

#### Send Notification
```yaml
service: script.awtrix_send_notification
data:
  text: "Alert!"
  color: [255, 0, 0]
  hold: true
  wakeup: true
  sound: "alarm"  # Optional
  icon: "5678"    # Optional
```

### Parameters

#### Text Display Parameters
- `text` (string): The text to display
- `app_name` (string): Name of the custom app (no spaces)
- `color` (array): RGB color values [R, G, B]
- `duration` (integer): Display duration in seconds
- `rainbow` (boolean): Enable rainbow text effect
- `icon` (string): Icon ID or base64 encoded 8x8 image

#### Notification Parameters
- `text` (string): Notification text
- `color` (array): RGB color values [R, G, B]
- `hold` (boolean): Keep notification until dismissed
- `wakeup` (boolean): Turn on matrix if off
- `sound` (string): Sound to play (RTTTL or MP3 filename)
- `icon` (string): Icon ID or base64 encoded 8x8 image

#### Mood Light Parameters
- `color` (array): RGB color values [R, G, B]
- `brightness` (integer): Brightness level (0-255)

## GPS Tracking

### Hardware
- Traccar-compatible GPS device
- Real-time position updates via cellular
- Battery-powered with solar charging

### Integration Points
- Location sensor: `sensor.glitchcube_location`
- GPS coordinates: `sensor.cube_tracker_latitude/longitude`
- Battery level: `sensor.cube_tracker_battery`

### Usage
```ruby
# Get current location in Ruby
client = HomeAssistantClient.new
location = client.state('sensor.glitchcube_location')
```

## Audio System

### Text-to-Speech
- Multiple voice options via Home Assistant
- Character-specific voices (Buddy, Jax, Lomi, Zorp)
- Service: `tts.cloud_say` or `tts.speak`

### Media Players
- `media_player.everywhere`: All speakers
- `media_player.square_voice`: Primary cube speaker
- Volume control and media playback

## LED Feedback System

### States
- `listening`: Blue pulsing
- `thinking`: Yellow spinning
- `speaking`: Green wave
- `completed`: White fade
- `error`: Red flash

### Control via Tools
```ruby
# Via conversation_feedback tool
execute_tool_call('conversation_feedback', 'set_state', { state: 'thinking' })
```

## Environmental Sensors

### Available Sensors
- Temperature: `sensor.cube_temperature`
- Humidity: `sensor.cube_humidity`
- Motion: `binary_sensor.cube_motion`
- Sound level: `sensor.cube_sound_level`

### Usage in Conversations
```ruby
# Enrich context with sensor data
context = enrich_context_with_sensors(context)
```

## Development Workflow

### 1. Creating a New Tool

```ruby
# lib/tools/my_new_tool.rb

class MyNewTool < BaseTool
  def self.name
    'my_new_tool'
  end

  def self.description
    'Does something useful. Args: action (string), target (string), options (object)'
  end

  def self.parameters
    {
      'action' => { 
        type: 'string',
        enum: %w[start stop status],
        description: 'Action to perform'
      },
      'target' => {
        type: 'string', 
        description: 'Target for the action'
      },
      'options' => {
        type: 'object',
        description: 'Additional options (JSON)'
      }
    }
  end

  def self.required_parameters
    %w[action]
  end

  def self.category
    'custom_integration'
  end

  def self.call(action:, target: nil, options: '{}')
    validate_required_params({ 'action' => action }, required_parameters)
    options = parse_json_params(options)

    case action
    when 'start'
      start_process(target, options)
    when 'stop'
      stop_process(target)
    when 'status'
      get_status(target)
    else
      format_response(false, "Unknown action: #{action}")
    end
  end

  private

  def self.start_process(target, options)
    # Implementation
    format_response(true, "Started #{target}")
  end
end
```

### 2. Testing Tools

```ruby
# Direct execution
result = Services::ToolRegistryService.execute_tool_directly('my_new_tool', {
  action: 'start',
  target: 'test_process'
})

# Through conversation (with persona)
conv = ConversationModule.new
result = conv.call(
  message: "Start the test process",
  context: { tools: ['my_new_tool'] },
  persona: 'buddy'
)
```

### 3. Adding to Personas

```ruby
# In lib/services/character_service.rb
buddy: {
  name: 'BUDDY',
  tools: %w[error_handling test_tool lighting_control music_control my_new_tool]
}
```

## Testing Hardware

### Console Commands
```ruby
# Test TTS
test_speak("Hello world", :buddy)

# Test display
ha.awtrix_display_text("Testing", color: [255, 0, 0])

# Test mood light
ha.awtrix_mood_light([0, 255, 0], brightness: 80)

# Get all states
ha.states
```

### Direct Home Assistant Testing
```bash
# SSH to Home Assistant VM
ssh root@glitch.local

# Test service calls
ha-cli service call script.awtrix_display_text --arguments text="Test"
```

### Integration Tests
Run the AWTRIX integration tests:
```bash
bundle exec rspec spec/lib/home_assistant_client_awtrix_spec.rb
```

## Best Practices

### Parameter Design

1. **Keep it simple**: Prefer flat parameter structures when possible
2. **Use enums**: Constrain string parameters to valid options
3. **JSON objects**: Use for complex nested data only
4. **Clear descriptions**: Explain what each parameter does and its format

### Error Handling

1. **Validate early**: Check all parameters before doing work
2. **Meaningful messages**: Provide clear error descriptions
3. **Graceful degradation**: Continue working when possible
4. **Use helpers**: Leverage `BaseTool` validation and formatting

### Integration Patterns

1. **Home Assistant**: Use `call_ha_service` for HA interactions
2. **External APIs**: Add circuit breakers for reliability
3. **State management**: Use `get_ha_state` for current system status
4. **Parallel execution**: Use `home_assistant_parallel` for batch operations

### Testing

1. **Mock integration**: Use `MockHomeAssistantClient` in tests
2. **Direct testing**: Test tools independently with `execute_tool_directly`
3. **Integration testing**: Test through conversation flow
4. **Error scenarios**: Test validation and error paths

## Troubleshooting

### Common Issues

1. **AWTRIX not responding**
   - Check MQTT connection
   - Verify power to display
   - Check Home Assistant logs

2. **TTS not working**
   - Verify media player is online
   - Check volume levels
   - Test with different TTS service

3. **GPS not updating**
   - Check cellular connection
   - Verify Traccar server status
   - Check device battery

4. **Tool not found**: Check file naming and class naming conventions
5. **Parameter errors**: Verify JSON parsing and required parameters
6. **HA connection**: Check Home Assistant URL and token configuration
7. **Permission errors**: Verify Home Assistant service permissions

### Debug Output

Enable debug mode to see tool loading and execution:

```bash
DEBUG=true bundle exec ruby app.rb
```

### Admin Interface

Use `/admin/advanced` for interactive tool testing:

1. Select persona to auto-load their tools
2. Enable specific tools manually  
3. Test tool calls in conversation context
4. View detailed logs and responses

## Security Considerations

1. **Input validation**: Always validate and sanitize parameters
2. **JSON parsing**: Use `parse_json_params` to prevent injection
3. **HA access**: Limit service calls to necessary entities
4. **Resource limits**: Implement timeouts and concurrency limits
5. **Error disclosure**: Don't expose sensitive information in error messages

## Performance

1. **Lazy loading**: Tools load on-demand during conversation
2. **Caching**: Tool registry caches discovered tools
3. **Parallel execution**: Use `home_assistant_parallel` for batch operations
4. **Timeouts**: Set appropriate timeouts for external calls
5. **Resource limits**: Maximum 5 parallel actions to prevent overload