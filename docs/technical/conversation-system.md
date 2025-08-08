# Conversation System Architecture

## Overview
The Glitch Cube conversation system uses a Phase 3.5 "Ultra-simple" architecture that prioritizes simplicity and reliability for voice interactions at Burning Man.

## Core Components

### ConversationModule
- Central orchestrator for all conversations
- Handles persona selection, memory injection, and tool execution
- Location: `lib/modules/conversation_module.rb`

### Session Management
- Ultra-simple approach: LLM decides when conversations end
- Session IDs provided by Home Assistant for voice interactions
- Auto-generated for non-voice interactions

### Tool-Based Execution
All hardware operations go through the tool system:
- **speech_tool**: Text-to-speech via Home Assistant
- **conversation_feedback**: LED state management
- **display_control**: AWTRIX display updates

### Memory System
- Memories stored in PostgreSQL with JSONB attributes
- Injected into system prompts for contextual conversations
- Service: `lib/services/memory_recall_service.rb`

## API Endpoints

### Primary Endpoint
`POST /api/v1/conversation`
- Main conversation endpoint
- Handles all interaction types
- Returns AI response with session management

### Deprecated Endpoints
These endpoints return migration guidance:
- `/api/v1/conversation/start`
- `/api/v1/conversation/continue`
- `/api/v1/conversation/end`

### Webhook Integration
`POST /api/v1/ha_webhook`
- Simplified forwarding to main conversation endpoint
- Handles Home Assistant voice events

## Conversation Flow

1. **Request arrives** via API or webhook
2. **Session created/retrieved** with ultra-simple logic
3. **System prompt built** with persona and memories
4. **LLM called** with conversation history
5. **Tools executed** if requested by LLM
6. **Response returned** with continuation flag

## Key Design Decisions

- **No complex state machines**: LLM decides conversation flow
- **Tool-based hardware control**: No direct HomeAssistant calls
- **Memory injection**: Contextual memories in system prompt
- **Safe defaults**: End conversation when unclear
- **Resilient to failures**: Fallback responses for all error cases

## Configuration

Key environment variables:
- `OPENROUTER_API_KEY`: LLM service access
- `HOME_ASSISTANT_URL`: Hardware control endpoint
- `HOME_ASSISTANT_TOKEN`: HA authentication
- `DATABASE_URL`: PostgreSQL connection

## Testing

Run conversation tests:
```bash
bundle exec rspec spec/modules/conversation_module_spec.rb
bundle exec rspec spec/lib/routes/api/conversation_spec.rb
```

Test in console:
```ruby
rake console
test_conversation("Hello!")
```