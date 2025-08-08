# Persona Development Guide

This guide covers how to develop, test, and iterate on AI personas for the Glitch Cube using both console interactions and the admin web interface.

## Overview

Glitch Cube personas are complete character definitions that include:
- **Personality & Voice**: TTS settings, speech patterns, behavioral traits
- **Tools & Capabilities**: Available functions and integrations  
- **Prompts & Context**: Character-specific system prompts and memory
- **Interaction Patterns**: How they respond to different situations

## Persona Architecture

### Character Service Integration

All persona configuration lives in `lib/services/character_service.rb`:

```ruby
buddy: {
  # Identity
  name: 'BUDDY',
  description: 'The Helper Cube - Naive assistant with broken profanity filter',
  
  # Voice & Speech
  tts_provider: :cloud,
  voice_id: 'DavisNeural',
  mood: :excited,
  speed: 110,
  volume: 0.8,
  voice_style: 'excited',
  
  # Personality
  personality_traits: {
    energy: :high,
    formality: :corporate_casual,
    humor: :unintentional
  },
  
  # Capabilities
  tools: %w[error_handling test_tool lighting_control music_control home_assistant display_control],
  
  # Audio cues
  chime: 'notification'
}
```

### Prompt Files

Each persona has a corresponding prompt file in `/prompts/`:
- `/prompts/buddy.txt` - BUDDY's system prompt
- `/prompts/jax.txt` - Jax's bartender personality
- `/prompts/lomi.txt` - LOMI's drag queen diva character

## Development Workflow

### 1. Console-Based Development

#### Quick Testing Script

Create a test script for rapid iteration:

```ruby
#!/usr/bin/env ruby
# test_persona.rb

require_relative 'lib/modules/conversation_module'
require_relative 'lib/services/character_service'

def test_persona(persona_name, test_messages)
  puts "🎭 Testing #{persona_name.upcase} persona"
  puts "=" * 50
  
  # Show persona configuration
  char_config = Services::CharacterService.get_character(persona_name)
  if char_config
    puts "📋 Configuration:"
    puts "   Name: #{char_config[:name]}"
    puts "   Voice: #{char_config[:voice_id]} (#{char_config[:mood]})"
    puts "   Tools: #{char_config[:tools]&.join(', ')}"
    puts "   Energy: #{char_config[:personality_traits]&.dig(:energy)}"
    puts
  end
  
  conv = ConversationModule.new
  session_id = "dev_#{persona_name}_#{Time.now.to_i}"
  
  test_messages.each_with_index do |message, i|
    puts "💬 Test #{i + 1}: #{message}"
    
    result = conv.call(
      message: message,
      context: {
        session_id: session_id,
        source: 'dev_console',
        persona: persona_name
      },
      persona: persona_name
    )
    
    puts "🤖 #{result[:response]}"
    puts "   Model: #{result[:model]} | Cost: $#{result[:cost]}"
    puts "   Tools available: #{result[:context]&.dig(:tools)&.size || 0}"
    puts
  end
end

# Test scenarios
buddy_tests = [
  "Hi BUDDY! Can you help me with something?",
  "Turn the lights red and play some music",
  "What tools do you have access to?",
  "Tell me about yourself"
]

test_persona('buddy', buddy_tests)
```

#### Interactive Console Session

```ruby
# Launch console
bundle exec rake console

# Create conversation module
conv = ConversationModule.new

# Set up persona context
context = {
  session_id: "dev_session_#{Time.now.to_i}",
  source: 'dev_console',
  persona: 'buddy'
}

# Interactive loop
loop do
  print "You: "
  message = gets.chomp
  break if message.downcase == 'exit'
  
  result = conv.call(message: message, context: context, persona: 'buddy')
  puts "BUDDY: #{result[:response]}"
  puts "Debug: #{result[:model]} | $#{result[:cost]} | #{result[:error]}" if result[:error]
end
```

#### Debugging Tools & Context

```ruby
# Check persona configuration
require_relative 'lib/services/character_service'
buddy_config = Services::CharacterService.get_character('buddy')
puts "BUDDY tools: #{buddy_config[:tools]}"

# Test tool registry integration
require_relative 'lib/services/tool_registry_service'
tools = Services::ToolRegistryService.get_tools_for_character('buddy')
puts "Available functions: #{tools.size}"
tools.each { |t| puts "  - #{t[:name]}: #{t[:description]}" }

# Test individual tools
result = Services::ToolRegistryService.execute_tool_directly('lighting_control', {
  action: 'set',
  color: [255, 0, 0],
  brightness: 128
})
puts "Tool result: #{result}"
```

### 2. Admin Interface Development

#### Accessing the Admin Interface

1. Start the application:
   ```bash
   bundle exec ruby app.rb
   ```

2. Navigate to: `http://localhost:4567/admin/advanced`

#### Advanced Testing Interface Features

**Persona Selection**
- Choose from dropdown: BUDDY, Jax, LOMI, etc.
- Auto-loads persona-specific tools and configuration
- Maintains conversation context across messages

**Tool Control**
- Manual tool enablement/disabling
- Real-time tool call observation
- Parallel execution testing

**Context Management**
- Session management and history
- Memory injection controls
- Custom JSON context injection
- Location and environmental context

**Real-time Debugging**
- Live activity logs
- API call tracing
- Error monitoring
- Performance metrics

#### Using the Admin Interface

1. **Start a Session**:
   ```
   Session Management → New Session
   ```

2. **Select Persona**:
   ```
   Persona/Mood → Select "BUDDY - Helper"
   ```

3. **Configure Tools** (optional):
   - Tools auto-load based on persona
   - Manually enable/disable as needed
   - View enabled tools in sidebar

4. **Test Interactions**:
   ```
   Message: "Hey BUDDY! Turn the lights blue and start playing music"
   ```

5. **Monitor Results**:
   - View conversation flow
   - Check tool calls and responses
   - Monitor costs and performance
   - Review error logs

#### Advanced Features

**Memory Testing**:
```
Custom Context: {"location": "Center Camp", "time_of_day": "evening"}
Skip Memory Injection: [unchecked]
```

**Tool Debugging**:
```
Enable Tools: ✓ Lighting ✓ Music ✓ Home Assistant
Message: "What can you control in this cube?"
```

**Context Injection**:
```json
{
  "custom_mood": "excited",
  "user_name": "Dave",
  "event_context": "Burning Man 2024",
  "battery_level": 85
}
```

## Development Patterns

### 1. Iterative Persona Development

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Prompt Design │───▶│  Console Test   │───▶│  Admin Refine   │
│   Character def │    │  Basic behavior │    │  Full context   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                        │                        │
         │                        ▼                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Deploy & Test │◀───│  Tool Integration│◀───│  Voice Testing  │
│   Real hardware │    │  Function calls │    │  TTS evaluation │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 2. Testing Methodology

**Phase 1: Core Personality**
- Basic conversational responses
- Personality trait expression
- Voice and speech patterns
- Error handling behavior

**Phase 2: Tool Integration**  
- Individual tool testing
- Multi-tool orchestration
- Error recovery with tools
- Context-aware tool usage

**Phase 3: Environmental Integration**
- Hardware interaction testing
- Home Assistant integration
- Real-world scenario testing
- Performance optimization

### 3. Common Testing Scenarios

```ruby
# Personality tests
personality_tests = [
  "Tell me about yourself",
  "What's your personality like?", 
  "How do you handle problems?",
  "What makes you unique?"
]

# Tool interaction tests
tool_tests = [
  "What can you control?",
  "Turn the lights red",
  "Play some music", 
  "Show me the current status",
  "Do several things at once"
]

# Error handling tests  
error_tests = [
  "Do something impossible",
  "Turn on the nonexistent lights",
  "Play music that doesn't exist",
  "Control something you can't access"
]

# Context awareness tests
context_tests = [
  "Where are we right now?",
  "What time is it?",
  "Remember our last conversation",
  "How are you feeling today?"
]
```

## Debugging & Troubleshooting

### Common Issues

**Tools Not Loading**
```ruby
# Check character configuration
Services::CharacterService.get_character_tools('buddy')

# Verify tool registry
Services::ToolRegistryService.discover_tools

# Check for typos in tool names
```

**Personality Not Showing**
- Check `/prompts/{persona}.txt` exists
- Verify persona name matches character service
- Test with neutral persona first

**Voice/TTS Issues**  
- Verify Home Assistant TTS configuration
- Check voice_id and provider settings
- Test with different voices

**Memory/Context Problems**
- Review system prompt injection
- Check context size limits
- Verify session management

### Debug Output

Enable comprehensive debugging:

```bash
# Environment variables
DEBUG=true 
RACK_ENV=development
HOME_ASSISTANT_MOCK=false

# Launch with debugging
bundle exec ruby app.rb
```

Look for debug output:
```
🔧 Auto-loaded 6 tools for persona 'buddy'
🧪 Mock HA: light.turn_on with {:entity_id=>"light.cube", :rgb_color=>[255, 0, 0]}
💬 Conversation request: "Turn the lights red"
```

### Performance Monitoring

```ruby
# In admin interface, monitor:
# - Response times (target < 2s)
# - Tool execution time
# - API costs per interaction  
# - Error rates by persona

# Console monitoring
result = conv.call(message: "test", persona: 'buddy')
puts "Response time: #{result[:response_time_ms]}ms"
puts "Cost: $#{result[:cost]}"
puts "Tokens: #{result[:tokens]}"
```

## Best Practices

### Persona Design

1. **Consistent Character**: Maintain personality across all interactions
2. **Tool Alignment**: Match tools to character capabilities and knowledge
3. **Voice Matching**: Align TTS settings with personality traits
4. **Error Personality**: Handle errors in character-appropriate ways

### Development Process

1. **Start Simple**: Begin with basic conversational responses
2. **Add Complexity Gradually**: Layer in tools and advanced features
3. **Test Edge Cases**: Handle errors and unexpected inputs
4. **Performance Test**: Monitor costs and response times
5. **Real-world Test**: Deploy to hardware for final validation

### Code Organization

```
/prompts/
  buddy.txt          # System prompt
  jax.txt
  lomi.txt

/lib/services/
  character_service.rb    # All persona configs

/test/
  personas/
    buddy_test.rb     # Automated persona tests
    test_scenarios.rb # Common test patterns
```

### Documentation

Document each persona with:
- **Character overview** and inspiration
- **Key personality traits** and behaviors  
- **Tool capabilities** and use cases
- **Voice settings** and speech patterns
- **Development notes** and known issues

## Advanced Techniques

### Dynamic Context Injection

```ruby
# Inject real-time environmental data
context = {
  session_id: session_id,
  persona: 'buddy',
  current_location: get_gps_location,
  battery_level: get_battery_status,
  ambient_temperature: get_temperature_sensor,
  nearby_sounds: analyze_audio_environment,
  time_context: {
    burning_man_day: calculate_burn_day,
    event_phase: determine_event_phase
  }
}
```

### Multi-Persona Conversations

```ruby
# Simulate persona interactions
def persona_dialogue(persona1, persona2, topic)
  conv = ConversationModule.new
  
  # Persona 1 starts
  context1 = { persona: persona1, session_id: "dialogue_#{Time.now.to_i}" }
  response1 = conv.call(message: topic, context: context1, persona: persona1)
  
  # Persona 2 responds
  context2 = { persona: persona2, session_id: context1[:session_id] }  
  response2 = conv.call(message: response1[:response], context: context2, persona: persona2)
  
  return [response1, response2]
end
```

### A/B Testing Personas

```ruby
# Compare persona variations
def compare_personas(message, personas)
  results = {}
  
  personas.each do |persona|
    result = conv.call(
      message: message,
      persona: persona,
      context: { session_id: "compare_#{persona}_#{Time.now.to_i}" }
    )
    
    results[persona] = {
      response: result[:response],
      cost: result[:cost],
      response_time: result[:response_time_ms]
    }
  end
  
  results
end

# Usage
comparison = compare_personas(
  "Turn the lights blue and play music",
  ['buddy', 'jax', 'lomi']
)
```

This guide provides a comprehensive framework for developing, testing, and refining AI personas for the Glitch Cube installation. Use both console and admin interface approaches to build engaging, reliable characters that enhance the art installation experience.