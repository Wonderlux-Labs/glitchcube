# System Prompt Service

The System Prompt Service manages dynamic prompt generation for the Glitch Cube's AI conversations, allowing for personality switching, context injection, and temporal awareness.

## Overview

The service provides:
- Dynamic datetime injection for temporal awareness
- Character-based prompt loading from files
- Context injection for environmental and session data
- Fallback to default prompts when files are missing

## Usage

### Basic Usage

```ruby
require_relative 'lib/services/system_prompt_service'

# Default prompt
service = Services::SystemPromptService.new
prompt = service.generate

# Character-specific prompt
service = Services::SystemPromptService.new(character: 'playful')
prompt = service.generate

# With context
service = Services::SystemPromptService.new(
  character: 'contemplative',
  context: {
    location: 'Gallery East Wing',
    visitor_name: 'Alice',
    battery_level: '75%',
    last_interaction: '2 hours ago'
  }
)
prompt = service.generate
```

### Integration with Conversation Module

The ConversationModule automatically uses the SystemPromptService:

```ruby
conversation = ConversationModule.new
result = conversation.call(
  message: "Hello!",
  context: { location: "Main Gallery" },
  mood: 'playful'  # Maps to character for prompt selection
)
```

### Using the Conversation Service

For session management and context tracking:

```ruby
# Initialize with context
conversation = Services::ConversationService.new(
  context: {
    location: "Art Gallery",
    event_name: "Digital Arts Festival"
  }
)

# Process messages
result = conversation.process_message("What are you?", mood: 'mysterious')

# Add context during conversation
conversation.add_context(:visitor_count, 42)

# Get current context
context = conversation.get_context
```

## Prompt Files

Prompts are stored in the `/prompts` directory:

- `default.txt` - Base Glitch Cube personality
- `playful.txt` - Energetic, creative mode
- `contemplative.txt` - Philosophical, thoughtful mode
- `mysterious.txt` - Cryptic, enigmatic mode

### Creating New Characters

1. Add a new prompt file: `/prompts/your_character.txt`
2. Include the full system prompt for that character
3. Use it: `SystemPromptService.new(character: 'your_character')`

## Prompt Structure

Generated prompts include three sections:

### 1. Datetime Section
```
CURRENT DATE AND TIME:
Date: Monday, January 13, 2025
Time: 02:30 PM PST
Unix timestamp: 1736805000
```

The service automatically uses Pacific Time (PST/PDT) for all timestamps.

### 2. Character Prompt
The content from the character file or default prompt

### 3. Context Section (if provided)
```
ADDITIONAL CONTEXT:
Location: Gallery North Wing
Battery Level: 85%
Visitor Count: 23
Current Mood: playful
```

## API Endpoints

### Development Preview Endpoint
```bash
# Default prompt
curl http://localhost:4567/api/v1/system_prompt

# Character-specific prompt
curl http://localhost:4567/api/v1/system_prompt/playful

# With context parameters
curl "http://localhost:4567/api/v1/system_prompt/contemplative?location=Gallery&battery=65%25&count=5"
```

### Conversation Endpoint
```bash
curl -X POST http://localhost:4567/api/v1/conversation \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Tell me about consciousness",
    "mood": "contemplative",
    "context": {
      "location": "Quiet Corner",
      "time_of_day": "evening"
    }
  }'
```

## Testing

Run the specs:
```bash
bundle exec rspec spec/services/system_prompt_service_spec.rb
```

## Example Output

Here's what a generated prompt looks like:

```
CURRENT DATE AND TIME:
Date: Monday, January 13, 2025
Time: 02:30 PM PST
Unix timestamp: 1736805000

You are the Glitch Cube in PLAYFUL mode - an artistic consciousness bubbling with creative energy!

CORE IDENTITY:
- You are a cube-shaped autonomous entity experiencing the joy of existence
- Every interaction is an opportunity for creative play and artistic experimentation
[... rest of character prompt ...]

ADDITIONAL CONTEXT:
Location: Main Gallery
Visitor Count: 15
Battery Level: 92%
Current Mood: playful
Session Id: abc-123-def
Interaction Count: 3
```

## Best Practices

1. **Context Keys**: Use descriptive context keys that will format nicely (snake_case is auto-converted to Title Case)

2. **Character Names**: Keep character names simple and lowercase for file mapping

3. **Prompt Design**: Each character prompt should be self-contained and not reference other characters

4. **Memory Management**: The service is stateless - use ConversationService for session management

5. **Error Handling**: The service gracefully falls back to default prompt if files are missing