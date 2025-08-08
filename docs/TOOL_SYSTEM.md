# Tool System Documentation

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

## Development Workflow

### 1. Creating a New Tool

```ruby
# lib/tools/my_new_tool.rb
require_relative 'base_tool'

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

## Debugging

### Debug Output

Enable debug mode to see tool loading and execution:

```bash
DEBUG=true bundle exec ruby app.rb
```

### Common Issues

1. **Tool not found**: Check file naming and class naming conventions
2. **Parameter errors**: Verify JSON parsing and required parameters
3. **HA connection**: Check Home Assistant URL and token configuration
4. **Permission errors**: Verify Home Assistant service permissions

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