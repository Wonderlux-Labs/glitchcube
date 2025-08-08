# Glitch Cube Documentation

## Quick Start
- [Main README](../README.md) - Project overview and setup
- [CLAUDE.md](../CLAUDE.md) - AI development instructions
- [Architecture Overview](./ARCHITECTURE.md) - System design and components

## Developer Documentation

### Core Systems
- [Conversation System](./technical/conversation-system.md) - AI conversation architecture
- [Tool System](./TOOL_SYSTEM.md) - LLM function calling framework
- [Hardware Integration](./technical/hardware-integration.md) - Physical device control

### Technical References
- [Environment Variables](./ENVIRONMENT_VARIABLES.md) - Configuration reference
- [Home Assistant Integration](./technical/home_assistant_integration.md) - HA API details
- [AI Framework (Desiru)](./technical/desirue_framework.md) - ReAct agent system
- [GPS Implementation](./technical/gps_real_time_implementation.md) - Location tracking

### API Documentation
- [Home Assistant Endpoints](./technical/home_assistant_api_endpoints.md) - HA API reference
- [System Prompt Service](./technical/system_prompt_service.md) - Prompt generation

## Operational Documentation

### Deployment & Configuration
- [Deployment Guide](./DEPLOYMENT.md) - Complete deployment instructions
- [Database Configuration](./operational/database-config.md) - PostgreSQL setup
- [Sidekiq Configuration](./operational/sidekiq-config.md) - Background jobs

### Monitoring & Maintenance
- [Admin Interface Guide](./operational/admin-interface-guide.md) - Testing conversations and tools
- [Health Monitoring](./operational/health-monitoring.md) - System health checks
- [Uptime Kuma Setup](./operational/uptime-kuma.md) - Service monitoring
- [GitHub Webhooks](./operational/github-webhooks.md) - CI/CD integration

## Personas & Content

### Character Documentation
- [Persona Development Guide](./personas/README.md) - Creating and managing personas
- [General Instructions](./personas/general-instructions.md) - Base personality rules
- [Art Philosophy](./personas/art-philosophy.md) - Creative direction

### Individual Personas
- [Buddy](./personas/buddy.md) - The helpful assistant
- [Jax](./personas/jax.md) - The surly bartender
- [Lomi](./personas/lomi.md) - The drag queen
- [Zorp](./personas/zorp.md) - The party bro

## Home Assistant Configuration
- [Entity Reference](../config/homeassistant/ENTITIES.md) - HA entities list
- [Integration Map](../config/homeassistant/INTEGRATION_MAP.md) - Service mappings

## Additional Resources
- [TTS Voice Mapping](./tts_voice_mapping.md) - Voice configuration
- [Cube Settings Reference](./cube_settings_reference.md) - Hardware settings
- [AWTRIX Integration](./technical/awtrix_integration.md) - LED display details
- [Location Configuration](./technical/location_configuration.md) - GPS setup

## Development Tools

### Testing
```bash
# Run all tests
bundle exec rspec

# Test conversations in console
rake console
test_conversation("Hello!")
```

### Common Tasks
```bash
# Deploy to production
rake deploy:smart

# Check system status
rake status

# Access Home Assistant VM
ssh root@glitch.local
```

## Documentation Standards

- **Technical docs**: Implementation details, API references
- **Operational docs**: Deployment, monitoring, configuration
- **Persona docs**: Character development, creative content
- **User-facing**: How to interact with the system

## Contributing
When updating documentation:
1. Keep it concise and practical
2. Include code examples
3. Update this index if adding new files
4. Remove outdated content aggressively

---
*Last updated: January 2025*