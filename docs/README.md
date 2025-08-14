# 🎲 Glitch Cube Documentation

A streamlined documentation structure for the autonomous interactive art installation.

## 📚 Documentation Structure

### 🚀 Quick Start Guides
- [Main README](../README.md) - Project overview and setup
- [CLAUDE.md](../CLAUDE.md) - AI development instructions  
- [Architecture Overview](./reference/ARCHITECTURE.md) - System design and components

### 📖 User Guides
- [Tool System & Hardware Integration](./guides/tool-integration.md) - Complete tool and hardware guide
- [Home Assistant Integration](./guides/home-assistant.md) - HA configuration and API reference
- [Testing Guide](./guides/testing.md) - Comprehensive testing with VCR
- [Persona Development](./guides/PERSONA_SWITCHING.md) - Creating and managing personas
- [Camera Vision Setup](./guides/camera_vision_setup.md) - Computer vision configuration
- [Location Configuration](./guides/location_configuration.md) - GPS and positioning
- [MariaDB Setup](./guides/mariadb_setup.md) - Database configuration
- [Context & Memory](./guides/summarization_and_context.md) - Memory system

### 📋 Reference Documentation
- [Environment Variables](./reference/ENVIRONMENT_VARIABLES.md) - Configuration reference
- [Configuration Guide](./reference/CONFIGURATION.md) - System configuration
- [Rake Tasks](./reference/RAKE_TASKS.md) - Available rake commands
- [TTS Voice Mapping](./reference/tts_voice_mapping.md) - Voice configuration
- [Integration Summary](./reference/glitchcube_integration_summary.md) - Technical overview

### 🔧 Operational Documentation
- [Deployment Guide](./operational/DEPLOYMENT.md) - Complete deployment instructions
- [Database Configuration](./operational/database-config.md) - PostgreSQL setup
- [Sidekiq Configuration](./operational/sidekiq-config.md) - Background jobs
- [Admin Interface Guide](./operational/admin-interface-guide.md) - Testing conversations and tools
- [Health Monitoring](./operational/health-monitoring.md) - System health checks
- [Uptime Kuma Setup](./operational/uptime-kuma.md) - Service monitoring
- [GitHub Webhooks](./operational/github-webhooks.md) - CI/CD integration

### 🎭 Personas & Content
- [Persona Development Guide](./personas/README.md) - Creating and managing personas
- [General Instructions](./personas/general-instructions.md) - Base personality rules
- [Art Philosophy](./personas/art-philosophy.md) - Creative direction
- [Buddy](./personas/buddy.md) - The helpful assistant
- [Jax](./personas/jax.md) - The surly bartender
- [Lomi](./personas/lomi.md) - The drag queen
- [Zorp](./personas/zorp.md) - The party bro

### 🎯 Core Systems (Technical)
- [Conversation System](./technical/conversation-system.md) - AI conversation architecture
- [Conversation Flows](./technical/conversation-flows.md) - Interaction patterns
- [Conversation Index](./technical/CONVERSATION_DOCS_INDEX.md) - Complete conversation docs
- [System Prompt Service](./technical/system_prompt_service.md) - Prompt generation

### 📊 Additional Resources
- [Cube Settings Reference](./cube_settings_reference.md) - Hardware settings
- [GPS Architecture](./gps_architecture.md) - Location tracking system
- [Hardware List](./EXISTING_SERVICES_AND_HARDWARE.md) - Complete hardware inventory
- [TODO List](./TODO.md) - Development roadmap
- [Overview](./overview.md) - Project summary

## 🛠️ Development Commands

```bash
# Development
bin/dev                    # Start development server (auto-reload + Sidekiq)
bin/console               # Interactive console with app loaded
bin/rspec                 # Run all tests
bin/rspec --vcr-override  # Re-record all VCR cassettes

# Testing
bin/rspec --vcr-none      # CI mode (no cassettes)
VCR_RECORD=true bin/rspec # Record specific test cassettes

# Production
bin/prod                  # Start production server
rake deploy:push["msg"]   # Deploy to production
rake health:check         # Check system status

# Console Testing
bin/console
test_conversation("Hello!")
```

## 📋 Documentation Organization

The documentation has been restructured into four clear categories:

1. **📖 User Guides** - Step-by-step how-to documentation
2. **📋 Reference** - Technical specifications and configuration
3. **🔧 Operational** - Deployment and maintenance procedures  
4. **🎭 Personas** - Character development and creative content

## 🧹 Cleanup Summary

**Deleted 17 obsolete files:**
- 6 completed planning documents (architecture specs, refactor summaries)
- 5 implementation artifacts (GPS tracker prototypes)
- 3 one-time analysis documents
- 3 redundant testing pattern files

**Created 3 consolidated guides:**
- `guides/tool-integration.md` - Complete tool & hardware documentation
- `guides/home-assistant.md` - Full HA integration guide
- `guides/testing.md` - Comprehensive testing with VCR patterns

**Result:** 75+ scattered files → ~30 organized, current files

---
*Documentation restructured: January 2025*