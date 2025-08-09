# Glitch Cube

[![Test Suite](https://github.com/yourusername/glitchcube/workflows/Test%20Suite/badge.svg)](https://github.com/yourusername/glitchcube/actions)
[![Lint](https://github.com/yourusername/glitchcube/workflows/Lint/badge.svg)](https://github.com/yourusername/glitchcube/actions)

An autonomous interactive art installation - a self-contained "smart cube" that engages with participants through conversation, requests transportation, and builds relationships over multi-day events.

## Overview

Glitch Cube is an AI-powered interactive art piece that combines physical hardware with conversational AI to create unique experiences at events. The cube develops its own personality, remembers past interactions, and engages with participants in unexpected ways.

## Quick Start

### Prerequisites

- **Ruby 3.3+** with Bundler
- **PostgreSQL** or **SQLite** for database
- **Redis** for background jobs and caching
- **Home Assistant** for hardware control (optional in development)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/glitchcube.git
cd glitchcube

# Install dependencies
bundle install

# Setup database
bundle exec rake db:create
bundle exec rake db:migrate

# Copy environment variables
cp .env.example .env
# Edit .env with your API keys and configuration
```

### Running the Application

```bash
# Development mode with auto-reload and Sidekiq
bin/dev

# Or run components separately
bundle exec ruby app.rb           # Main application
bundle exec sidekiq               # Background jobs
```

### Testing

```bash
# Run full test suite
bundle exec rspec

# Run with coverage
COVERAGE=true bundle exec rspec

# Run linter
bundle exec rubocop
```

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- [Architecture Overview](docs/ARCHITECTURE.md) - System design and components
- [Deployment Guide](docs/DEPLOYMENT.md) - Production deployment instructions
- [Docker Setup](docs/DOCKER_SETUP.md) - Docker deployment for Raspberry Pi
- [Environment Variables](docs/ENVIRONMENT_VARIABLES.md) - Configuration reference
- [Tool System](docs/TOOL_SYSTEM.md) - LLM tool execution framework

### Development Guides

- [VCR Testing Guide](docs/technical/vcr_testing.md) - API testing with VCR
- [Personas](docs/personas/) - Personality configuration system
- [Operational Docs](docs/operational/) - Event operations and troubleshooting

## Key Features

- **Conversational AI**: Multi-turn conversations with memory and context
- **Hardware Integration**: Controls lights, sensors, and actuators via Home Assistant
- **Event Awareness**: GPS tracking, movement detection, and environmental sensing
- **Personality System**: Configurable personas with unique traits and behaviors
- **Memory & Learning**: Persistent memory across interactions and events

## Architecture

- **Web Framework**: Sinatra with modular architecture
- **AI/LLM**: OpenRouter API with multiple model support
- **Background Jobs**: Sidekiq with Redis
- **Hardware Control**: Home Assistant integration
- **Database**: PostgreSQL (production) / SQLite (development)
- **Testing**: RSpec with VCR for API testing

## Development

### Project Structure

```
glitchcube/
├── app.rb                 # Main application entry
├── config/               # Configuration files
├── lib/                  # Core business logic
│   ├── models/          # Database models
│   ├── services/        # Service objects
│   └── modules/         # Shared modules
├── spec/                # Test suite
├── docs/                # Documentation
└── data/                # Runtime data and contexts
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for your changes
4. Ensure all tests pass
5. Submit a pull request

## Deployment

The application is deployed on a Mac Mini for production use. For alternative deployment options including Raspberry Pi with Docker, see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

## License

[Your License Here]