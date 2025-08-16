# Async Tools Configuration Guide

This document covers the configuration options for the async conversation flow implemented in Phase 5 of the async conversation system.

## Environment Variables

### Main Feature Flag

- **`ENABLE_ASYNC_TOOLS`** (boolean, default: `true`)
  - Master switch for async tool execution
  - Set to `false` to disable async flow entirely and fall back to synchronous execution
  - Automatically disabled in test environment

### Timeout Configuration

- **`ASYNC_IMMEDIATE_TIMEOUT`** (float, default: `1.0`)
  - Maximum time (in seconds) for generating immediate acknowledgment response
  - Controls how long the system waits before giving up on fast response generation
  - Should be kept low (< 2 seconds) for natural conversation flow

- **`ASYNC_BACKGROUND_TIMEOUT`** (float, default: `30.0`) 
  - Maximum time (in seconds) for background tool execution
  - Controls how long tools are allowed to run before timing out
  - Increase for complex operations, decrease for faster failure detection

- **`ASYNC_FOLLOW_UP_DELAY`** (float, default: `2.0`)
  - Delay (in seconds) before speaking follow-up results
  - Prevents immediate follow-up from interrupting the initial acknowledgment
  - Tune based on average TTS playback time

### Thread Management

- **`ASYNC_MAX_THREADS`** (integer, default: `3`)
  - Maximum number of concurrent async tool execution threads
  - Prevents resource exhaustion under high load
  - Consider your hardware capabilities when setting this

- **`ASYNC_THREAD_CLEANUP_TIMEOUT`** (float, default: `60.0`)
  - Time (in seconds) before forcefully cleaning up stale threads
  - Prevents memory leaks from stuck background operations
  - Should be longer than `ASYNC_BACKGROUND_TIMEOUT`

### Fallback Behavior

- **`ASYNC_FALLBACK_TO_SYNC`** (boolean, default: `true`)
  - Whether to fall back to synchronous execution when async fails
  - Recommended to keep `true` for production reliability
  - Set to `false` for strict async-only testing

## Configuration Access

In Ruby code, access these values through the configuration system:

```ruby
# Check if async tools are enabled
GlitchCube.config.async_tools_enabled?

# Get timeout values
GlitchCube.config.async_immediate_timeout
GlitchCube.config.async_background_timeout
GlitchCube.config.async_follow_up_delay

# Thread management
GlitchCube.config.async_max_threads
GlitchCube.config.async_thread_cleanup_timeout

# Fallback behavior
GlitchCube.config.async_fallback_to_sync?
```

## Example Environment Configuration

### Production Settings (Optimized for Reliability)
```bash
# Enable async tools with conservative timeouts
ENABLE_ASYNC_TOOLS=true
ASYNC_IMMEDIATE_TIMEOUT=1.5
ASYNC_BACKGROUND_TIMEOUT=45.0
ASYNC_FOLLOW_UP_DELAY=2.5
ASYNC_MAX_THREADS=2
ASYNC_THREAD_CLEANUP_TIMEOUT=90.0
ASYNC_FALLBACK_TO_SYNC=true
```

### Development Settings (Faster Iteration)
```bash
# Enable async with shorter timeouts for development
ENABLE_ASYNC_TOOLS=true
ASYNC_IMMEDIATE_TIMEOUT=0.5
ASYNC_BACKGROUND_TIMEOUT=15.0
ASYNC_FOLLOW_UP_DELAY=1.0
ASYNC_MAX_THREADS=3
ASYNC_THREAD_CLEANUP_TIMEOUT=30.0
ASYNC_FALLBACK_TO_SYNC=true
```

### Testing Settings (Disabled for Consistent Tests)
```bash
# Disable async for predictable test execution
ENABLE_ASYNC_TOOLS=false
```

## Tuning Recommendations

### For Fast Response Times
- Decrease `ASYNC_IMMEDIATE_TIMEOUT` to 0.5-1.0 seconds
- Decrease `ASYNC_FOLLOW_UP_DELAY` to 1.0-1.5 seconds
- Keep `ASYNC_BACKGROUND_TIMEOUT` moderate (15-30 seconds)

### For Reliability
- Increase `ASYNC_BACKGROUND_TIMEOUT` to 45-60 seconds
- Increase `ASYNC_THREAD_CLEANUP_TIMEOUT` to 90-120 seconds
- Keep `ASYNC_FALLBACK_TO_SYNC=true`
- Limit `ASYNC_MAX_THREADS` to 2-3

### For Resource-Constrained Environments
- Set `ASYNC_MAX_THREADS=1` or `ASYNC_MAX_THREADS=2`
- Decrease `ASYNC_BACKGROUND_TIMEOUT` to 20-30 seconds
- Consider `ENABLE_ASYNC_TOOLS=false` if resources are very limited

## Monitoring and Debugging

### Log Messages to Watch For

```bash
# Async flow decision
grep "Routing to async tool flow" logs/glitchcube.log

# Thread management
grep "Starting tool execution with timeout" logs/glitchcube.log
grep "Thread completed successfully" logs/glitchcube.log

# Fallback scenarios
grep "Using synchronous flow" logs/glitchcube.log
```

### Performance Metrics

Monitor these metrics in production:
- Response time for immediate acknowledgments (should be < 1 second)
- Background execution completion rate
- Thread cleanup efficiency
- Fallback-to-sync frequency

### Common Issues and Solutions

**Issue**: Async flow never triggers
- **Check**: `ENABLE_ASYNC_TOOLS=true`
- **Check**: Not in test environment
- **Check**: Not in conversation extraction mode
- **Check**: Message length > 10 characters
- **Check**: Message doesn't contain `?` (questions use sync)

**Issue**: Background execution times out
- **Solution**: Increase `ASYNC_BACKGROUND_TIMEOUT`
- **Solution**: Check Home Assistant connectivity
- **Solution**: Verify tool execution logic

**Issue**: Thread buildup/memory leaks
- **Solution**: Decrease `ASYNC_THREAD_CLEANUP_TIMEOUT`
- **Solution**: Decrease `ASYNC_MAX_THREADS`
- **Solution**: Monitor thread completion logs

**Issue**: Follow-up TTS interrupts immediate response
- **Solution**: Increase `ASYNC_FOLLOW_UP_DELAY`
- **Solution**: Check TTS service response times

## Testing the Configuration

Use the provided test script to verify configuration:

```bash
# Run async conversation test
ruby scripts/testing_scripts/test_async_conversation.rb

# Run RSpec tests
bin/rspec spec/services/conversation/async_flow_spec.rb
```

## Integration with Home Assistant

The async flow integrates with Home Assistant through:

1. **Immediate TTS**: Direct `tts.cloud_say` service call for acknowledgment
2. **Background Tools**: Home Assistant service calls via tool execution engine  
3. **Follow-up TTS**: Direct `speak_as_persona` calls with persona-specific voices

Ensure your Home Assistant configuration supports:
- TTS service (cloud or local)
- Entity control services (light, media_player, etc.)
- Custom scripts for queued TTS (optional)

## Migration from Synchronous Flow

To migrate from sync to async:

1. **Start Conservative**: Use production settings above
2. **Monitor Performance**: Watch logs and response times
3. **Tune Gradually**: Adjust timeouts based on observed behavior
4. **Test Thoroughly**: Use test script and manual verification
5. **Rollback Plan**: Keep `ASYNC_FALLBACK_TO_SYNC=true` enabled

## Future Enhancements

Potential configuration additions:
- Per-persona timeout settings
- Tool-specific timeout overrides
- Dynamic timeout adjustment based on load
- Priority queuing for different tool types
- Retry configuration for failed background execution