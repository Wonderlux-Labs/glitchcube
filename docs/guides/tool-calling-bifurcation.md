# Tool Calling Pattern Bifurcation

This guide explains how to use the tool calling pattern bifurcation feature for A/B testing different tool execution approaches.

## Overview

The tool calling bifurcation feature allows you to switch between two different tool execution patterns:

1. **`:default`** - Traditional direct tool execution through ToolExecutor
2. **`:back_to_hass`** - Tool execution via Home Assistant conversation agent

This enables A/B testing to compare performance, reliability, and functionality between the two approaches.

## Configuration

### Environment Variable

Set the tool calling pattern using the `TOOL_CALLING_PATTERN` environment variable:

```bash
# Use default pattern (traditional execution)
export TOOL_CALLING_PATTERN=default

# Use Home Assistant proxy pattern
export TOOL_CALLING_PATTERN=back_to_hass
```

### Programmatic Configuration

You can also check the current pattern programmatically:

```ruby
# Check current pattern
GlitchCube.config.tool_calling_pattern
# => :default or :back_to_hass

# Pattern is automatically converted from string to symbol
```

## How It Works

### Default Pattern (`:default`)

```
User Message → LLM → Tool Calls → ToolExecutionEngine → ToolExecutor → Hardware
```

- Tool calls are executed directly through the existing ToolExecutor
- Each tool is executed individually with direct API calls
- Results are formatted and returned to the LLM for final response

### Back to HASS Pattern (`:back_to_hass`)

```
User Message → LLM → Tool Calls → ToolExecutionEngine → HomeAssistantToolProxy → HA Conversation Agent → Hardware
```

- Tool calls are converted to natural language requests
- Sent to Home Assistant's "claude background" conversation agent
- The agent executes tools and returns results
- Results are parsed and formatted for the final LLM response

## Usage Examples

### Switching Patterns

```ruby
# In your environment or configuration
ENV['TOOL_CALLING_PATTERN'] = 'back_to_hass'

# Process a conversation - will use Home Assistant proxy
result = Services::Conversation::FlowManager.new.process_conversation(
  message: 'Turn on the living room lights',
  context: { tools: [...] }
)
```

### A/B Testing Setup

```bash
# Terminal 1 - Test default pattern
export TOOL_CALLING_PATTERN=default
bin/dev

# Terminal 2 - Test back_to_hass pattern  
export TOOL_CALLING_PATTERN=back_to_hass
bin/dev
```

## Home Assistant Setup

For the `:back_to_hass` pattern to work, you need:

1. A conversation agent named "claude background" in Home Assistant
2. The agent should be configured to handle tool execution requests
3. Proper authentication tokens configured

### Example Home Assistant Configuration

```yaml
# configuration.yaml
conversation:
  intents:
    claude_background:
      - "Execute these tools: {tools}"
      - "Please execute: {request}"
```

## Monitoring and Debugging

### Logs

The system logs which pattern is being used:

```
[INFO] Starting tool execution cycle (pattern: :back_to_hass, session_id: abc123, tool_count: 2)
[INFO] Using Home Assistant tool proxy for execution
```

### Performance Tracking

Both patterns are tracked with timing information:

- **Default**: `"Finished tool execution cycle in 150ms"`
- **Back to HASS**: `"Finished HA tool execution cycle in 300ms"`

## Error Handling

### Default Pattern Errors

- Tool execution failures are retried according to `tool_retry` configuration
- Individual tool failures don't stop the entire cycle
- Detailed error messages are logged and returned

### Back to HASS Pattern Errors

- Home Assistant connection failures fall back to error results for all tools
- No individual tool retries (Home Assistant handles this internally)
- Simplified error reporting through the conversation agent

## Testing

### Unit Tests

```ruby
# Test default pattern
allow(GlitchCube.config).to receive(:tool_calling_pattern).and_return(:default)
result = tool_engine.execute_tool_calls(llm_response, session_id)

# Test back_to_hass pattern
allow(GlitchCube.config).to receive(:tool_calling_pattern).and_return(:back_to_hass)
result = tool_engine.execute_tool_calls(llm_response, session_id)
```

### Integration Tests

See `spec/integration/tool_calling_pattern_bifurcation_spec.rb` for complete integration test examples.

## Performance Considerations

### Default Pattern
- **Pros**: Direct execution, faster, more granular control
- **Cons**: Individual API calls, potential for partial failures

### Back to HASS Pattern  
- **Pros**: Consolidated execution, Home Assistant handles complexity
- **Cons**: Additional network hop, dependency on conversation agent

## Rollback Strategy

To quickly rollback to the default pattern:

```bash
# Remove or comment out the environment variable
# export TOOL_CALLING_PATTERN=back_to_hass

# Or explicitly set to default
export TOOL_CALLING_PATTERN=default

# Restart the application
bin/dev
```

## Metrics for A/B Testing

Track these metrics when comparing patterns:

1. **Response Time**: Time from tool calls to results
2. **Success Rate**: Percentage of successful tool executions  
3. **Error Rate**: Frequency and types of failures
4. **User Experience**: Response quality and accuracy
5. **System Load**: Resource usage and scalability impact

## Best Practices

1. **Test Both Patterns**: Use the same test scenarios for fair comparison
2. **Monitor Logs**: Watch for pattern-specific error patterns
3. **Gradual Rollout**: Test with limited user groups before full deployment
4. **Performance Baseline**: Establish metrics before switching patterns
5. **Rollback Plan**: Always have a quick rollback strategy ready

## Troubleshooting

### Pattern Not Switching
- Verify environment variable is set correctly
- Check that variable is loaded (restart application)
- Confirm config conversion (string → symbol) is working

### Home Assistant Connection Issues
- Verify HA URL and token configuration
- Check that "claude background" agent exists
- Test HA conversation API directly

### Unexpected Behavior
- Check logs for pattern confirmation messages
- Verify mock configurations in tests
- Ensure both patterns handle the same tool types