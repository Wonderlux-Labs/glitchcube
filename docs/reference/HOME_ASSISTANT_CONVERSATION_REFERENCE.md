# Home Assistant Conversation Agent Reference

## 🏗️ Architecture Overview

**WE OWN THE CONVERSATION AGENT CODE** - This is our custom component deployed in Home Assistant, so we can modify the response structure however we want!

### Core Components

1. **GlitchCube Conversation Agent** (`config/homeassistant/custom_components/glitchcube_conversation/`)
   - Custom Home Assistant conversation entity
   - Routes conversation requests to our Sinatra app
   - Handles the response formatting for Home Assistant

2. **GlitchCube Sinatra App** (`/api/v1/conversation` endpoint)
   - Runs our personas (Lomi, Buddy, Jax, Zorp)
   - Handles action extraction and execution
   - Returns structured responses to the conversation agent

## 🔄 Current Conversation Flow

```
User Speech → Home Assistant → GlitchCube Conversation Agent → Sinatra App
                                    ↓
Home Assistant ← Response Processing ← Action Execution ← LLM Response
```

### Detailed Flow

1. **User speaks** to Home Assistant satellite/device
2. **Home Assistant** processes speech-to-text
3. **GlitchCube Conversation Agent** receives the text
4. **Agent calls Sinatra** at `/api/v1/conversation` with payload:
   ```json
   {
     "message": "Turn the lights blue",
     "context": {
       "session_id": "voice_ABC123",
       "conversation_id": "HA_conversation_id", 
       "device_id": "satellite_1",
       "language": "en",
       "voice_interaction": true,
       "timestamp": "2025-01-15T10:45:00Z"
     }
   }
   ```

5. **Sinatra processes** with persona (Lomi, etc.)
6. **Actions extracted** and executed via Claude conversation agent
7. **Sinatra returns** response data
8. **HA Agent formats** response for Home Assistant
9. **Home Assistant speaks** the response via TTS

## 📤 Current Response Structure

### What Sinatra Returns to HA Agent
```json
{
  "success": true,
  "data": {
    "response": "Oh h-h-hunty, I'm turning those lights fabulous blue!",
    "continue_conversation": true,
    "persona": "lomi",
    "tts_voice": "AriaNeural",
    "tts_provider": "cloud"
  }
}
```

### What HA Agent Returns to Home Assistant
```python
conversation.ConversationResult(
    conversation_id=user_input.conversation_id,
    response=intent_response,  # Contains speech text
    continue_conversation=continue_conversation,
)
```

## 🎯 Enhanced Architecture Opportunities

Since we own the conversation agent, we can enhance it to support:

### 1. Multi-Turn Action Conversations
```python
# Enhanced response structure we can implement:
{
  "success": true,
  "data": {
    "response": "Oh h-h-hunty, I'm turning those lights blue!",
    "continue_conversation": true,
    "persona": "lomi",
    "action_results": {
      "executed_actions": ["Turn lights blue", "Set brightness to 80%"],
      "claude_feedback": "Successfully set both lights to blue. The brightness looks perfect for mood lighting.",
      "follow_up_required": false
    },
    "conversation_state": {
      "awaiting_user_feedback": true,
      "context": "lighting_adjustment"
    }
  }
}
```

### 2. Claude Feedback Integration
Our conversation agent can:
- Store Claude's execution feedback in HA conversation context
- Trigger follow-up calls to Sinatra with Claude's results
- Create conversation threads about tool execution

### 3. Enhanced TTS Control
Since we control the agent, we can:
- Set persona-specific voices dynamically
- Control TTS parameters per response
- Add audio effects for glitch personas

## 🔧 Implementation Ideas

### Feedback Loop Architecture
```python
# In our conversation agent
async def async_process(self, user_input):
    # Initial conversation
    result1 = await self._call_sinatra(user_input.text)
    
    # If actions were executed, get Claude's feedback
    if result1.get("action_results"):
        feedback_payload = {
            "message": f"Claude executed: {result1['action_results']['claude_feedback']}",
            "context": {
                "conversation_type": "action_feedback",
                "original_request": user_input.text,
                "action_results": result1["action_results"]
            }
        }
        
        # Get Lomi's reaction to the results
        result2 = await self._call_sinatra_feedback(feedback_payload)
        
        # Combine responses
        combined_response = f"{result1['response']} {result2['response']}"
        
    return conversation.ConversationResult(...)
```

### Claude Integration Point
```python
# Where Claude reports back execution results
{
  "claude_execution_results": {
    "success_actions": [
      {"action": "Turn lights blue", "result": "Success", "details": "All 3 lights changed to blue"},
      {"action": "Set brightness 80%", "result": "Success", "details": "Brightness adjusted"}
    ],
    "failed_actions": [],
    "claude_observations": "The lighting looks great! The blue creates a nice ambiance.",
    "suggestions": ["You might want to dim them further for movie watching"],
    "questions": []
  }
}
```

## 🎭 Persona-Specific Enhancements

Since we control the agent, we can make each persona handle feedback differently:

### Lomi (Glitch Bitch)
- Dramatic reactions to successful actions: "Yasss hunty, those lights are SERVING!"
- Sassy responses to failures: "Ugh, these basic lights can't handle my fabulousness!"
- Glitch effects when tools fail

### Buddy (Helper)
- Enthusiastic about successes: "Great job! Everything worked perfectly!"
- Apologetic about failures: "Sorry about that! Let me try a different approach!"
- Offers alternatives when things fail

### Jax (Bartender)
- Gruff acknowledgments: "Yeah, lights are blue. Happy now?"
- Sarcastic about failures: "Figures. Nothing works in this place."
- Minimal responses to success

### Zorp (Slacker God)
- Chill reactions: "Cool, man. The lights are like, totally blue now."
- Cosmic philosophy about failures: "Sometimes the universe just says no, dude."
- Laid-back about everything

## 🚀 Next Steps

1. **Enhance Sinatra Response Structure**
   - Add `action_results` field with Claude feedback
   - Include conversation state tracking
   - Add persona-specific response formatting

2. **Upgrade Conversation Agent**
   - Add feedback loop handling
   - Implement multi-turn action conversations
   - Add enhanced TTS control

3. **Create Action Result Events**
   - Fire Home Assistant events when actions complete
   - Allow other automations to react to tool results
   - Enable cross-device coordination

## 💡 Key Insights

1. **We own the entire pipeline** - can modify any part of it
2. **Claude's feedback is valuable** - users should be able to discuss results
3. **Personas should react differently** - to both success and failure
4. **Multi-turn conversations** - about tool execution are natural
5. **Home Assistant integration** - can be much deeper than current implementation

This architecture gives us complete control over the conversation experience while leveraging Home Assistant's robust voice pipeline infrastructure.