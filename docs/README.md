# Glitch Cube Documentation

## 📚 Documentation Index

Welcome to the Glitch Cube documentation! This autonomous interactive art installation combines Ruby/Sinatra, AI conversation, and IoT hardware control.

### 🚀 Getting Started

- **[Overview](overview.md)** - Project overview and architecture
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Complete deployment guide for Mac Mini + VMware setup
- **[ENVIRONMENT_CONFIG.md](ENVIRONMENT_CONFIG.md)** - Environment configuration system
- **[ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md)** - Complete list of environment variables

### 🔧 Configuration & Setup

- **[DATABASE_CONFIG.md](DATABASE_CONFIG.md)** - Database setup and configuration
- **[SIDEKIQ_CONFIG.md](SIDEKIQ_CONFIG.md)** - Background job processing setup
- **[cube_settings_reference.md](cube_settings_reference.md)** - Ruby Settings module reference
- **[docker_development.md](docker_development.md)** - Docker development environment (optional)
- **[development_notes.md](development_notes.md)** - macOS development tips and tricks

### 🤖 AI & Conversation System

- **[TOOL_SYSTEM.md](TOOL_SYSTEM.md)** - Complete tool system documentation: architecture, parameters, validation, and development patterns
- **[PERSONA_DEVELOPMENT.md](PERSONA_DEVELOPMENT.md)** - Guide to developing AI personas: console testing, admin interface, and best practices

- **[characters/](characters/)** - Persona documentation
  - [GENERAL INSTRUCTIONS](characters/GENERAL%20INSTRUCTIONS%20FOR%20ALL%20CUBE%20PERSONAS.md) - Base personality traits
  - [BUDDY](characters/BUDDY%20-%20THE%20HELPER%20CUBE%20(NAIVE%20ASSISTANT%20PERSONA).md) - Helpful assistant persona
  - [JAX](characters/JAX%20THE%20JUKE%20-%20SURLY%20BARTENDER%20PERSONA.md) - Surly bartender persona
  - [LOMI](characters/LOMI%20-%20THE%20GLITCH%20BITCH%20(DRAG%20QUEEN%20PERSONA).md) - Drag queen persona
  - [ZORP](characters/ZORP%20-%20THE%20SLACKER%20GOD%20(PARTY%20BRO%20PERSONA).md) - Party bro persona

- **[context/](context/)** - Contextual information
  - [art_philosophy.md](context/art_philosophy.md) - Artistic vision and philosophy
  - [glitch_cube_identity.txt](context/glitch_cube_identity.txt) - Cube identity context

- **[sample_conversation_flow.md](sample_conversation_flow.md)** - Example conversation flows
- **[tts_voice_mapping.md](tts_voice_mapping.md)** - Text-to-speech voice configuration

### 🏠 Home Assistant Integration

- **[HEALTH_MONITORING.md](HEALTH_MONITORING.md)** - Health monitoring architecture and flows
- **[home_assistant_entities.md](home_assistant_entities.md)** - Entity definitions and usage
- **[camera_vision_setup.md](camera_vision_setup.md)** - Camera and vision AI setup
- **[technical/home_assistant_integration.md](technical/home_assistant_integration.md)** - Integration details
- **[technical/home_assistant_api_endpoints.md](technical/home_assistant_api_endpoints.md)** - API reference

### 📍 Location & GPS Features

- **[gps_architecture.md](gps_architecture.md)** - GPS tracking architecture
- **[technical/location_configuration.md](technical/location_configuration.md)** - Location setup
- **[technical/gps_real_time_implementation.md/](technical/gps_real_time_implementation.md/)** - Real-time tracking implementation
  - Burning Man specific GPS tracking and visualization

### 🔧 Technical Documentation

- **[technical/](technical/)** - Deep technical guides
  - [awtrix_integration.md](technical/awtrix_integration.md) - LED matrix display integration
  - [desirue_framework.md](technical/desirue_framework.md) - Desiru AI framework details
  - [glitchcube_integration_summary.md](technical/glitchcube_integration_summary.md) - System integration overview
  - [mariadb_setup.md](technical/mariadb_setup.md) - MariaDB configuration
  - [summarization_and_context.md](technical/summarization_and_context.md) - Context management
  - [system_prompt_service.md](technical/system_prompt_service.md) - System prompt handling

### 🔄 Persistence & Data

- **[persistence_options.md](persistence_options.md)** - Data persistence strategies
- **[implementation_plan.md](implementation_plan.md)** - Project implementation phases

### 🛠️ Development Tools

- **[github-webhook-setup.md](github-webhook-setup.md)** - GitHub webhook configuration
- **[self_healing_error_handler.md](self_healing_error_handler.md)** - Error recovery system

### 📝 Additional Resources

- **[important_info.md](important_info.md)** - Production URLs and critical info
- **[../CLAUDE.md](../CLAUDE.md)** - AI assistant instructions for development
- **[../README.md](../README.md)** - Main project README

## 🗂️ Deprecated Documentation

Old or outdated documentation has been moved to `/deprecated/` for historical reference:
- Legacy deployment scripts (Docker/Raspberry Pi) → `/deprecated/deployment/`
- Beacon monitoring service → `/deprecated/beacon/`

## 📖 Documentation Standards

When adding new documentation:
1. Use clear, descriptive filenames
2. Include a title and overview section
3. Keep technical docs in `/docs/technical/`
4. Keep persona docs in `/docs/characters/`
5. Update this index when adding new files
6. Move deprecated docs to `/deprecated/` with a `DEPRECATION_NOTICE.md`

## 🔍 Quick Reference

### Key Configuration Files
- `.env.defaults` - Default environment variables
- `.env.example` - Example environment setup
- `config/initializers/config.rb` - Application configuration
- `config/homeassistant/` - Home Assistant YAML configs

### Important Rake Tasks
```bash
rake deploy:full    # Full deployment
rake deploy:check   # Check what needs deploying
rake hass:deploy    # Deploy Home Assistant config
rake host:deploy    # Deploy Sinatra app
```

### API Endpoints
- `GET /health` - Health check endpoint
- `GET /health/push` - Push health to Uptime Kuma
- `POST /api/v1/conversation` - Main conversation endpoint
- `POST /api/webhook/glitchcube_update` - HA webhook endpoint

---

*Documentation last organized: January 2025*