# Architecture Consolidation Plan

## Executive Summary

This document outlines the consolidation plan for Glitch Cube's bidirectional conversation system. We are moving from a dual-responsibility architecture to a **Sinatra-centric** approach where Home Assistant handles STT (Speech-to-Text) and hardware control, while Sinatra becomes the centralized conversation intelligence with unified TTS and tool execution.

## Problem Statement

The current system has organically grown to have dual conversation flows:
- **Home Assistant**: Custom conversation agent as integration glue + some TTS calls
- **Sinatra**: Independent conversation processing + own TTS calls + tool execution

This creates confusion, duplicate execution paths, and architectural complexity. We need clear separation of concerns.

## Solution: Sinatra-Centric Architecture

### Architecture Decision
**Sinatra becomes the conversation brain**, Home Assistant remains the hardware interface.

**Why Sinatra-centric?**
- ✅ Keep HA satellite for compact STT functionality (user preference)
- ✅ Centralize conversation intelligence and persona logic
- ✅ Unified tool execution through LLM function calling
- ✅ Single source of truth for conversation state
- ✅ Simplified debugging and tracing

### High-Level Flow
```
User Speech → HA Satellite (STT) → HA Custom Agent (glue) → Sinatra (brains) → Response
                                                                  ↓
                                              Tools + TTS + Display Updates
```

## Multi-Turn Conversation Flow

### Session Management and State

**How Multi-Turn Conversations Work:**

1. **Session Creation**: First user interaction creates a `ConversationSession` with unique `session_id`
2. **State Persistence**: All messages, context, and metadata stored in PostgreSQL via ActiveRecord
3. **Conversation History**: Each LLM call includes previous messages for context continuity
4. **Session Lifecycle**: Sessions can be explicitly ended or timeout after inactivity

**Session Data Structure:**
```ruby
ConversationSession {
  session_id: "uuid",
  messages: [
    { role: "user", content: "Hello", persona: "buddy" },
    { role: "assistant", content: "Hi there!", persona: "buddy" }
  ],
  metadata: {
    ha_conversation_id: "ha-uuid",  # Maps to HA conversation
    voice_interaction: true,
    last_persona: "buddy",
    device_id: "satellite_01"
  }
}
```

### Triggering Listening Mode

**For multi-turn conversations, we can trigger HA to resume listening using Home Assistant service calls:**

```ruby
# After Sinatra processes response and wants to continue conversation
home_assistant.call_service(
  'assist_satellite', 
  'start_conversation',
  {
    entity_id: 'assist_satellite.glitchcube_satellite',
    # This starts the microphone listening for next user input
  }
)
```

**Service Call Options:**
- `assist_satellite.start_conversation` - Modern HA satellite approach
- `conversation.process` with `wait_for_response: true` - Legacy approach  
- Custom automation triggers for specific conversation flows

### Role of Custom Conversation Agent

**Does this eliminate the need for the custom conversation agent?**

**No** - the custom conversation agent remains essential as **integration glue**, but contains **zero conversation logic**.

**Custom Agent Responsibilities:**
```yaml
# configuration.yaml
conversation:
  intents:
    glitchcube:
      - service: http_request
        url: "http://sinatra:4567/api/v1/conversation"
        method: POST
        headers:
          Content-Type: "application/json"
        data:
          message: "{{ query }}"
          context:
            voice_interaction: true
            device_id: "{{ device_id }}"
            ha_conversation_id: "{{ conversation_id }}"
```

**The custom agent is pure glue** - it receives voice input from HA and forwards to Sinatra, then returns the response. No business logic, no intelligence, just HTTP forwarding.

## Implementation Phases

### Phase 1: Unify TTS Execution Paths ✅ COMPLETED
- [x] Replace `ConversationModule.speak_response()` with `CharacterService.speak()` calls
- [ ] Update admin routes to use consistent CharacterService TTS path  
- [ ] Remove deprecated `speak_file()` method from CharacterService

### Phase 2: Standardize Tool Execution
- [ ] Remove tool execution fallback mechanisms from ConversationModule
- [ ] Standardize on LLM tool calling approach via ToolExecutor
- [ ] Remove dual execution paths (tools OR direct service calls)

### Phase 3: Simplify HA Integration  
- [ ] Remove bidirectional webhook complexity from HA integration
- [ ] Consolidate conversation endpoints (`/api/v1/conversation` becomes primary)
- [ ] Simplify custom HA conversation agent to pure HTTP forwarding

### Phase 4: Final Cleanup
- [ ] Remove deprecated methods and cleanup dual execution paths
- [ ] Update documentation to reflect Sinatra-centric architecture
- [ ] Performance testing and optimization

## Technical Benefits

### Before (Dual Architecture)
```
User → HA Satellite → HA Agent → ???
                        ↓
                  Sometimes Sinatra, sometimes HA TTS
                        ↓  
                  Different tool execution paths
```

### After (Sinatra-Centric)
```
User → HA Satellite → HA Agent (glue) → Sinatra (brains) → Unified Response
                                           ↓
                                    Single TTS path
                                    Single tool execution  
                                    Single conversation state
```

### Advantages
- **Single Source of Truth**: All conversation logic in Sinatra
- **Simplified Debugging**: One conversation flow to trace
- **Unified Personas**: CharacterService handles all TTS with voice personalities
- **Tool Consistency**: All hardware control through LLM function calling
- **Session Management**: PostgreSQL stores all conversation state
- **Easier Testing**: Integration tests target single conversation endpoint

## Multi-Turn Flow Example

```ruby
# Turn 1: User says "Hello"
POST /api/v1/conversation
{
  "message": "Hello",
  "context": {
    "voice_interaction": true,
    "device_id": "satellite_01"
  }
}
# → Creates session, responds, stores message history

# Turn 2: User says "What's the weather?"  
POST /api/v1/conversation
{
  "message": "What's the weather?",
  "context": {
    "session_id": "existing-uuid",  # Same session
    "voice_interaction": true
  }
}
# → Loads conversation history, includes previous messages in LLM context
# → LLM sees: [system_prompt, "Hello", "Hi there!", "What's the weather?"]
# → Processes with full context, responds with weather info

# Turn 3: Continue conversation
# → Same pattern, building conversation history
```

## Listening Mode Integration

```ruby
# In ConversationModule after processing response:
if continue_conversation && context[:voice_interaction]
  # Trigger HA to resume listening
  @home_assistant.call_service(
    'assist_satellite',
    'start_conversation', 
    { entity_id: context[:device_id] }
  )
end
```

This creates seamless multi-turn voice conversations where each response can trigger the next listening cycle.

## Conclusion

This consolidation provides clear architectural boundaries:
- **Home Assistant**: STT, hardware control, integration glue
- **Sinatra**: Conversation intelligence, TTS, tool execution, session management

The custom conversation agent remains but becomes a thin HTTP forwarding layer with zero business logic, maintaining the separation of concerns while eliminating architectural confusion.