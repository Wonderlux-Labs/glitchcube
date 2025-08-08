# Admin Interface Guide

## Overview
The Glitch Cube admin interface provides simple, form-based tools for testing conversations, TTS, memories, and system tools. No JavaScript required - everything works with basic HTML forms and page refreshes.

## Access Points

### Simple Test Interface (Recommended)
**URL**: `/admin/test`
- Clean, minimal interface
- Form-based interactions
- No JavaScript required
- Server-side rendering

### Legacy Interfaces (Complex)
- `/admin/simple` - JavaScript-heavy interface (being phased out)
- `/admin/advanced` - Complex debugging tools
- `/admin/tools` - Direct tool testing

## Main Test Interface (`/admin/test`)

### Testing Conversations

1. **Send a Test Message**
   - Enter your message in the text area
   - Select a character persona (Buddy, Jax, Lomi, or Zorp)
   - Optionally provide a session ID to continue an existing conversation
   - Click "Send Message"
   - The AI response will appear below with session details

2. **Understanding the Response**
   ```
   Response: [AI's response text]
   
   Session: abc123-def456  (unique conversation ID)
   Persona: buddy          (character used)
   Cost: $0.0012          (API cost)
   Continue: true/false   (whether AI expects continuation)
   ```

3. **Continuing a Conversation**
   - Copy the Session ID from a previous response
   - Paste it into the "Session ID" field
   - Send your next message
   - The AI will maintain context from the previous messages

### Testing Text-to-Speech

1. Enter the text you want spoken
2. Select the character voice
3. Click "Test TTS"
4. The audio will play through the cube's speakers
5. Success/failure status appears below

### Viewing Conversations

**Recent Conversations** appear at the bottom of the main page showing:
- Character persona used
- Session ID
- Number of messages
- Total cost
- Start time
- Link to view full session

Click "View Full Session" to see:
- Complete message history
- Token usage and costs
- Tool calls made
- Continuation flags
- Form to continue the conversation

## Session Management (`/admin/test/sessions`)

### Viewing All Sessions
- Lists last 20 conversations
- Shows key metrics for each
- Click any session ID to view details

### Session Details Page
Shows complete conversation including:
- User messages (blue border)
- Assistant responses (green border)
- Tool calls (orange border)
- Metadata (costs, tokens, continuation flags)
- Form to continue the conversation

## Memory Viewer (`/admin/test/memories`)

### Recent Memories
Displays the 20 most recent memories showing:
- Content of the memory
- Category (interaction, observation, etc.)
- Location where it occurred
- Emotional intensity (0-100%)
- Recall count (how often it's been used)
- Creation timestamp

Memories are automatically extracted from conversations and injected into future interactions for context.

## Tool Testing (`/admin/test/tools`)

### Available Tools
Lists all registered tools with:
- Tool name
- Description
- Category (hardware, information, etc.)

### Testing a Tool
1. Click on a tool name
2. Fill in the required parameters
3. Click "Execute"
4. View the result or error message

Common tools to test:
- `weather_tool` - Get current weather
- `sensor_status` - Check cube sensors
- `battery_level` - Check power status
- `conversation_feedback` - Set LED state

## Common Testing Workflows

### 1. Test a Complete Conversation Flow
```
1. Go to /admin/test
2. Send "Hello, who are you?"
3. Note the session ID
4. Send "Tell me about yourself" with same session ID
5. Verify context is maintained
6. Check "Continue" flag behavior
```

### 2. Test Different Personas
```
1. Send same message to each character:
   - Buddy: Helpful, eager response
   - Jax: Gruff, bartender style
   - Lomi: Dramatic, performative
   - Zorp: Laid-back, party vibe
2. Verify voice and personality match
```

### 3. Test Memory Injection
```
1. View recent memories at /admin/test/memories
2. Start new conversation mentioning a memory topic
3. Check if AI references relevant memories
4. Verify memory recall count increases
```

### 4. Test Hardware Integration
```
1. Test TTS with each character voice
2. Go to /admin/test/tools
3. Test conversation_feedback tool with different LED states
4. Test display_control tool with text messages
```

## Troubleshooting

### No Response from AI
- Check `/health` endpoint for system status
- Verify OpenRouter API key is configured
- Check error logs in `/admin/errors`

### TTS Not Working
- Verify Home Assistant is running
- Check media player is online
- Test with simple message first
- Check volume levels

### Session Not Found
- Session IDs expire after 24 hours
- Use exact session ID (case-sensitive)
- Check if conversation was actually saved

### Memory Not Appearing
- Memories extract asynchronously
- Wait a few seconds and refresh
- Check Sidekiq is running for background jobs

## Best Practices

1. **Start Simple**: Test basic "Hello" first
2. **Use Real Scenarios**: Test actual user interactions
3. **Test Edge Cases**: Long messages, special characters, multiple tools
4. **Monitor Costs**: Check session costs regularly
5. **Clean Test Data**: Periodically clear old test sessions

## System Health Checks

Before testing, verify system health:
1. Visit `/health` - All services should show "healthy"
2. Check `/admin/test` loads without errors
3. Verify recent conversations display
4. Test simple TTS to confirm audio works

## API Integration

For automated testing, use these endpoints directly:

```bash
# Test conversation
curl -X POST http://localhost:4567/admin/test/conversation \
  -d "message=Hello&persona=buddy"

# Test TTS
curl -X POST http://localhost:4567/admin/test/tts \
  -d "message=Test&character=buddy"

# Get session details
curl http://localhost:4567/admin/session_history?session_id=xxx
```

## Notes

- All interactions are logged for debugging
- Test sessions are real and affect memory/learning
- Costs are actual API costs (use sparingly)
- The simple interface is intentionally minimal
- No JavaScript means reliable operation