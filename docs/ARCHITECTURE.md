# Glitch Cube System Architecture

## Overview
Glitch Cube is an autonomous interactive art installation for Burning Man - a self-aware cube that engages participants through AI-powered conversations, requests transportation when needed, and builds relationships over the course of the event.

## Core Philosophy
**"This is fundamentally simple"** - We're building glue code between APIs. The magic happens in the LLM responses and Home Assistant automations, not in complex Ruby logic.

## System Components

### 1. Ruby/Sinatra Backend
- **Purpose**: API gateway and conversation orchestrator
- **Key Services**:
  - `ConversationModule`: Central conversation handler
  - `LLMService`: OpenRouter API integration
  - `HomeAssistantClient`: Hardware control interface
  - `ToolExecutor`: Function calling for LLM tools

### 2. Home Assistant VM
- **Purpose**: Hardware abstraction and automation
- **Components**:
  - Voice pipeline integration
  - AWTRIX LED display control
  - GPS tracking via Traccar
  - Environmental sensors
  - TTS/audio output

### 3. AI/LLM Layer
- **Provider**: OpenRouter (multiple models)
- **Personas**: Buddy, Jax, Lomi, Zorp
- **Features**:
  - Context-aware conversations
  - Memory injection
  - Tool calling for hardware control

### 4. Data Persistence
- **PostgreSQL**: Conversations, memories, sessions
- **Redis**: Background job queues
- **Sidekiq**: Async job processing

## Architecture Principles

### 1. Simplicity First
- No complex state machines
- LLM drives conversation flow
- Minimal business logic in Ruby

### 2. Resilience
- Circuit breakers for external services
- Fallback responses for all failures
- Offline mode capabilities

### 3. Tool-Based Execution
- All hardware operations via tools
- No direct service calls from conversation logic
- Standardized tool interface

## Data Flow

```
User Speech → Home Assistant → Webhook → Sinatra → LLM → Tools → Response
                                            ↓
                                      PostgreSQL
                                      (memories)
```

## Key Design Decisions

### Phase 3.5 Architecture
- **Ultra-simple session management**: LLM decides continuation
- **Consolidated endpoints**: Single `/api/v1/conversation`
- **Tool-based hardware control**: No fallback paths
- **Memory injection**: Contextual memories in prompts

### Development Approach
1. Integration over implementation
2. Test actual API flows with VCR
3. Visibility through logging and tracing
4. Fast iteration over perfect abstractions

## Deployment Architecture

### Production Environment
- **Host**: Mac Mini M2 with VMware Fusion
- **VM**: Home Assistant OS
- **Network**: Starlink primary, cellular backup
- **Power**: 24-hour battery with solar

### Service Layout
```
Mac Mini (Host)
├── Sinatra App (Port 4567)
├── PostgreSQL (Port 5432)
├── Redis (Port 6379)
└── VMware Fusion
    └── Home Assistant VM
        ├── Core (Port 8123)
        ├── Voice Pipeline
        └── MQTT Broker
```

## Security Considerations
- API authentication via tokens
- Environment-based configuration
- No secrets in code
- Restricted VM network access

## Performance Targets
- Conversation response: <2 seconds
- TTS playback: <1 second
- Tool execution: <500ms
- Offline fallback: Immediate

## Monitoring & Observability
- Health endpoints for circuit breakers
- Uptime Kuma for service monitoring
- Structured logging with tags
- Cost tracking per conversation

## Future Considerations
- Multi-cube synchronization
- Crowd analytics
- Extended memory system
- Real-time location sharing

## Related Documentation
- [Deployment Guide](./DEPLOYMENT.md)
- [Conversation System](./technical/conversation-system.md)
- [Environment Variables](./ENVIRONMENT_VARIABLES.md)
- [Tool System](./TOOL_SYSTEM.md)