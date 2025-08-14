# Conversation System Architecture

## Overview

The Glitch Cube conversation system has been completely refactored from a monolithic design to a modular, service-oriented architecture. This new design addresses the scalability, maintainability, and testability issues of the previous implementation while maintaining the core goal of reliable voice interactions at Burning Man.

The architecture uses a central `ConversationFlowManager` that orchestrates specialized services for different aspects of conversation processing, from LLM interactions to tool execution and state management.

## Architectural Principles

- **Separation of Concerns**: Each service has a single, well-defined responsibility
- **Modular Design**: Components can be tested, modified, and extended independently
- **Robust Error Handling**: Centralized error handling with context preservation
- **Resilient to Failures**: Fallback responses and recovery mechanisms
- **Tool-Based Execution**: All hardware operations go through the tool system
- **Memory-Enhanced**: Contextual memories injected for personalized interactions

## Core Components

### 1. ConversationModule (`lib/modules/conversation_module.rb`)

The main entry point that provides a simple interface for conversation processing:

```ruby
# Persona switching
ConversationModule.switch_persona('buddy')
ConversationModule.buddy.call(message: "Hello!")

# Direct conversation processing
ConversationModule.new.call(
  message: "How's the weather?",
  context: { session_id: "abc123", persona: "jax" }
)
```

**Responsibilities:**
- Provide simple class methods for persona switching
- Initialize and delegate to ConversationFlowManager
- Handle visual feedback coordination (LED states)
- Manage top-level error handling and logging

### 2. ConversationFlowManager (`lib/services/conversation/conversation_flow_manager.rb`)

The central orchestrator that manages the entire conversation lifecycle:

```ruby
@flow_manager = Services::Conversation::ConversationFlowManager.new
result = @flow_manager.process_conversation(
  message: user_input,
  context: enriched_context,
  persona: 'buddy'
)
```

**Responsibilities:**
- Coordinate between all conversation services
- Manage the conversation execution cycle
- Handle tool call workflows (LLM → Tools → Follow-up LLM)
- Build and return final response data
- Centralized error handling for the conversation flow

### 3. LLMInteractionManager (`lib/services/conversation/llm_interaction_manager.rb`)

Standardizes all communication with Large Language Models:

```ruby
llm_manager = Services::LLMInteractionManager.new
messages = llm_manager.prepare_messages(history, system_prompt, user_message)
response = llm_manager.call_llm(messages: messages, llm_options: options)
```

**Responsibilities:**
- Message preparation and formatting
- Model selection based on context (tools vs. conversation)
- System prompt generation with context injection
- LLM API calls with proper logging and timing
- Response schema management for structured outputs

### 4. ToolExecutionEngine (`lib/services/conversation/tool_execution_engine.rb`)

Handles execution of tools requested by the LLM:

```ruby
tool_engine = Services::ToolExecutionEngine.new
result = tool_engine.execute_tool_calls(llm_response, session_id)
# Returns: { tool_results: [...], last_tool_calls: [...] }
```

**Responsibilities:**
- Parse and validate tool calls from LLM responses
- Execute tools via the existing ToolExecutor service
- Handle tool execution errors gracefully
- Format tool results for follow-up LLM calls
- Track tool execution for conversation metadata

### 5. ConversationHistoryManager (`lib/services/conversation/conversation_history_manager.rb`)

Manages conversation context and message history:

```ruby
history_manager = Services::Conversation::ConversationHistoryManager.new
context = history_manager.get_conversation_context(session)
truncated = history_manager.truncate_or_summarize_history(messages, session_id)
```

**Responsibilities:**
- Retrieve conversation context for LLM calls
- Intelligent history truncation and summarization
- Topic extraction from conversation content
- Conversation duration and metadata tracking
- Memory-efficient context management

### 6. ResponseProcessor (`lib/services/conversation/response_processor.rb`)

Validates and processes LLM responses:

```ruby
processor = Services::ResponseProcessor.new
response_data = processor.process_response(llm_response, persona_instance, session_id)
# Returns: { response: "...", continue_conversation: true, inner_thoughts: "..." }
```

**Responsibilities:**
- Extract response text from LLM outputs
- Determine conversation continuation flags
- Extract inner thoughts and metadata
- Generate fallback responses for malformed outputs
- Validate response structure and content

### 7. ConversationStateManager (`lib/services/conversation/conversation_state_manager.rb`)

Manages conversation state persistence and analytics:

```ruby
state_manager = Services::ConversationStateManager.new
session = state_manager.create_or_get_session(session_id, context)
state_manager.record_message(session: session, role: 'user', content: message)
analytics = state_manager.get_conversation_analytics(session_id)
```

**Responsibilities:**
- Session creation and retrieval
- Message recording with metadata
- Conversation analytics generation
- Performance metrics tracking
- Cost and token usage analysis

## Conversation Flow

### Standard Conversation Process

1. **Request Reception**: ConversationModule receives message and context
2. **Session Management**: StateManager creates/retrieves session
3. **Context Enrichment**: Historical context and memories loaded
4. **LLM Preparation**: InteractionManager builds messages and system prompt
5. **LLM Execution**: Primary LLM call with conversation history
6. **Tool Processing**: If tools are called, ToolExecutionEngine handles execution
7. **Follow-up LLM**: Second LLM call with tool results (if needed)
8. **Response Processing**: ResponseProcessor validates and extracts final response
9. **State Persistence**: Message and metadata saved to database
10. **Result Return**: Final structured response returned to caller

### Tool Execution Workflow

```mermaid
graph TD
    A[LLM Response with Tools] --> B[ToolExecutionEngine]
    B --> C[Parse Tool Calls]
    C --> D[Execute via ToolExecutor]
    D --> E[Format Results]
    E --> F[Second LLM Call]
    F --> G[Final Response]
```

When the LLM returns tool calls:
1. ToolExecutionEngine parses function calls and arguments
2. Each tool is executed individually with error handling
3. Results are formatted for LLM consumption
4. A follow-up LLM call is made with tool results
5. The final response from this second call is processed normally

## Integration Points

### Memory System Integration

The conversation system integrates with the memory system through:
- `Services::ContextEnrichmentService.enrich(context)` - Adds relevant memories to context
- System prompt injection with memory context
- Memory recall based on location, recency, and emotional intensity

### Tool System Integration

All hardware control goes through the tool system:
- **speech_tool**: Text-to-speech via Home Assistant
- **conversation_feedback**: LED state management
- **display_control**: AWTRIX display updates
- **sensor_tools**: Environmental data access
- **weather_tool**: Weather information retrieval

### Home Assistant Integration

- Webhook endpoint receives voice pipeline events
- Tool execution sends commands to HA via REST API
- Session IDs provided by HA for voice interactions
- TTS output and LED control via HA automations

### Database Integration

- PostgreSQL with conversations, messages, and memories tables
- JSONB metadata storage for flexible conversation data
- Performance optimized queries for history retrieval
- Analytics data aggregation for admin interface

## API Endpoints

### Primary Endpoint
`POST /api/v1/conversation`
```json
{
  "message": "Hello, how are you?",
  "session_id": "optional-uuid",
  "persona": "buddy",
  "context": {
    "voice_interaction": true,
    "visual_feedback": true
  }
}
```

Response:
```json
{
  "response": "Hi there! I'm doing great...",
  "conversation_id": "uuid",
  "session_id": "uuid",
  "persona": "buddy",
  "continue_conversation": true,
  "model": "anthropic/claude-3-haiku",
  "cost": 0.0023,
  "tokens": { "prompt_tokens": 150, "completion_tokens": 45 }
}
```

### Webhook Integration
`POST /api/v1/ha_webhook`
- Receives Home Assistant voice events
- Automatically forwards to main conversation endpoint
- Handles session continuity for voice interactions

### Deprecated Endpoints
These endpoints now return migration guidance:
- `/api/v1/conversation/start`
- `/api/v1/conversation/continue`
- `/api/v1/conversation/end`

## Configuration

### Environment Variables
```bash
# LLM Service
OPENROUTER_API_KEY=your_key_here
HELICONE_API_KEY=optional_logging_key

# Home Assistant
HOME_ASSISTANT_URL=http://homeassistant:8123
HOME_ASSISTANT_TOKEN=your_ha_token

# Database
DATABASE_URL=postgresql://user:pass@host:5432/database
REDIS_URL=redis://localhost:6379/0

# Conversation Settings
CONVERSATION_TEMPERATURE=0.8
CONVERSATION_MAX_TOKENS=1500
CONVERSATION_TIMEOUT=20
```

### Model Configuration
Models are selected automatically based on context:
- **Tools Model**: For conversations requiring tool execution
- **Default Model**: For standard conversations
- **Premium Model**: For complex reasoning or analysis

## Error Handling

The new architecture provides comprehensive error handling:

### Centralized Error Handler
`Services::ConversationErrorHandler` handles all conversation errors:
- LLM service failures and rate limits
- Tool execution errors
- Network timeouts and connectivity issues
- Malformed response handling
- Fallback response generation

### Circuit Breaker Integration
- Protects against cascading failures
- Auto-recovery after cooldown periods
- Service health monitoring
- Graceful degradation

### Recovery Mechanisms
- Automatic retry with exponential backoff
- Fallback personas for error responses
- Session preservation during errors
- User-friendly error messages

## Performance Considerations

### Memory Management
- Intelligent conversation history truncation
- Smart context summarization
- Lazy loading of conversation data
- Redis caching for frequently accessed data

### Cost Optimization
- Model selection based on task complexity
- Context compression for long conversations
- Token usage tracking and optimization
- Cost-aware response generation

### Database Optimization
- Proper indexing for conversation queries
- Efficient session management
- Batch operations for analytics
- Performance monitoring and alerting

## Testing Strategy

### Unit Tests
Each service component is tested in isolation:
```bash
bundle exec rspec spec/lib/services/conversation/
```

### Integration Tests
Test component interactions and data flow:
```bash
bundle exec rspec spec/integration/conversation_flow_spec.rb
```

### VCR Cassettes
All external API calls are recorded:
- LLM responses for consistent testing
- Tool execution results
- Home Assistant interactions
- Error scenarios and edge cases

### Console Testing
Interactive testing in development:
```ruby
# In bin/console
conversation = ConversationModule.buddy
result = conversation.call(message: "Test message")
puts result[:response]
```

## Monitoring and Observability

### Structured Logging
- Consistent tagging across all components
- Performance metrics and timing
- Error context preservation
- Session tracking throughout flow

### Analytics and Metrics
- Conversation success rates
- Response times and performance
- Cost tracking per conversation
- Tool usage patterns
- Persona effectiveness metrics

### Admin Interface Integration
- Real-time conversation monitoring
- Session browsing and search
- Error investigation tools
- Performance analytics dashboard

## Migration from Previous Architecture

The new architecture maintains backward compatibility while providing:

### Maintained APIs
- Main conversation endpoint unchanged
- Same response format and structure
- Existing persona switching mechanisms
- Tool integration points preserved

### Enhanced Capabilities
- Better error handling and recovery
- Improved performance and scalability
- Enhanced conversation analytics
- More flexible tool execution patterns
- Better testing and debugging support

### Breaking Changes
- Internal service interfaces updated
- Some advanced configuration options changed
- Logging formats enhanced with new metadata
- Admin interface with new analytics features

## Future Extensibility

The modular architecture enables:

### Plugin Architecture
- Custom conversation flow handlers
- Extensible tool execution patterns
- Pluggable response processing strategies
- Custom analytics and monitoring

### Advanced Features
- Multi-turn tool execution workflows
- Conversation branching and state machines
- Advanced context management strategies
- Integration with external knowledge bases
- Real-time conversation collaboration

## Debugging and Troubleshooting

### Common Issues and Solutions

**No response from LLM:**
- Check circuit breaker status
- Verify API key configuration
- Review error logs for rate limiting
- Check model availability

**Tool execution failures:**
- Verify Home Assistant connectivity
- Check tool configuration and availability
- Review tool execution logs
- Test tools individually

**Session not continuing:**
- Check `continue_conversation` flag in responses
- Verify session ID consistency
- Review conversation history for context
- Check persona configuration

**Memory not injecting:**
- Verify memory recall service configuration
- Check location sensor data
- Review memory database entries
- Test context enrichment service

### Debugging Commands

```bash
# Check system health
curl http://localhost:4567/api/health

# View recent conversations
bin/console
> Conversation.recent.limit(5)

# Test specific components
> Services::Conversation::ConversationFlowManager.new.process_conversation(...)

# Check service states
> Services::System::CircuitBreakerService.status
```

---

*Architecture implemented January 2025 - Replaces previous monolithic ConversationModule*