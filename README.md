# Glitch Cube

[![Test Suite](https://github.com/yourusername/glitchcube/workflows/Test%20Suite/badge.svg)](https://github.com/yourusername/glitchcube/actions)
[![Lint](https://github.com/yourusername/glitchcube/workflows/Lint/badge.svg)](https://github.com/yourusername/glitchcube/actions)

An autonomous interactive art installation - a self-contained "smart cube" that engages with participants through conversation, requests transportation, and builds relationships over multi-day events.

## Quick Start (Docker on Raspberry Pi 5)

### Prerequisites

1. **Raspberry Pi 5** with 8GB RAM recommended
2. **USB SSD** (recommended for 24/7 reliability) or high-quality SD card
3. **Raspberry Pi OS Lite** (64-bit) or Ubuntu Server
4. **Docker and Docker Compose** installed

### Install Docker on Raspberry Pi 5

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo apt install docker-compose -y

# Verify installation
docker --version
docker-compose --version
```

### Deploy Glitch Cube

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/glitchcube.git
cd glitchcube
```

2. **Configure environment variables**
```bash
cp .env.production.example .env
nano .env  # Edit with your API keys and settings
```

3. **Set up data directories**
```bash
# Create persistent data directories
mkdir -p data/production/{glitchcube,context_documents,postgres}
mkdir -p data/development/{glitchcube,context_documents}
mkdir -p data/test/{glitchcube,context_documents}

# Add initial context documents
cp -r data/context_documents/* data/production/context_documents/
```

Required variables:
- `OPENROUTER_API_KEY`: Your OpenRouter API key
- `HA_TOKEN`: Home Assistant long-lived access token (set after HA setup)
- `SESSION_SECRET`: Generate with `openssl rand -hex 64`
- `MASTER_PASSWORD`: Single password for all services (default: `glitchcube123`)

3. **Build and start the containers**
```bash
# Build the application image
docker-compose build

# Optional: Use multi-stage build for smaller image (saves ~100MB)
# docker build -f Dockerfile.multistage -t glitchcube:latest .

# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Check service health
docker-compose ps
```

4. **Set up auto-start on boot**
```bash
# Create systemd service
sudo nano /etc/systemd/system/glitchcube.service
```

Add the following content:
```ini
[Unit]
Description=Glitch Cube Docker Compose Application
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/pi/glitchcube
ExecStart=/usr/bin/docker-compose -f docker-compose.yml -f docker-compose.production.yml --profile management up
ExecStop=/usr/bin/docker-compose -f docker-compose.yml -f docker-compose.production.yml down
TimeoutStartSec=300
Restart=unless-stopped
RestartSec=30

[Install]
WantedBy=multi-user.target
```

Enable the service:
```bash
sudo systemctl enable glitchcube.service
sudo systemctl start glitchcube.service
```

## Data Persistence

Glitch Cube uses Docker volumes for data persistence with separate directories for each environment:

### Volume Structure
```
data/
├── production/          # Production data (persistent)
│   ├── homeassistant/  # Home Assistant config and data
│   ├── glitchcube/     # SQLite DB, session data
│   ├── context_documents/  # RAG documents, memories
│   └── postgres/       # PostgreSQL data (if using)
├── development/         # Development data (persistent)
│   ├── glitchcube/     # Dev SQLite DB, session data
│   └── context_documents/  # Dev RAG documents
├── test/               # Test data (ephemeral)
│   ├── glitchcube/
│   └── context_documents/
├── redis/              # Redis persistence
└── portainer/          # Portainer config
```

Note: Home Assistant only runs in production. Use `MOCK_HOME_ASSISTANT=true` for development/test.

### Environment-Specific Usage

**Development (default)**
```bash
docker-compose up -d
# Uses ./data/development/ with source code mounted
```

**Test**
```bash
docker-compose -f docker-compose.yml -f docker-compose.test.yml up -d
# Uses ./data/test/ with in-memory SQLite
```

**Production**
```bash
docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d
# Uses ./data/production/ without source code mount
```

## Development

### Using VS Code Dev Container

1. Install VS Code with Remote-Containers extension
2. Open the project folder
3. Click "Reopen in Container" when prompted
4. Development environment will be automatically configured

### Local Development (without Docker)

```bash
# Install dependencies
bundle install

# Run with mock Home Assistant
MOCK_HOME_ASSISTANT=true DEVELOPMENT_MODE=true bundle exec ruby app.rb

# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop
```

## Architecture

- **Sinatra App** (Port 4567): Main conversation engine with LLM service integration
- **Home Assistant**: Hardware control and sensor management
- **Redis**: Background job queue for Sidekiq
- **Sidekiq**: Async processing for long-running tasks
- **Portainer** (Optional): Web-based Docker management UI

## Environment Variables

See [docs/ENVIRONMENT_VARIABLES.md](docs/ENVIRONMENT_VARIABLES.md) for complete documentation of all environment variables.

## Monitoring

### View container logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f glitchcube
docker-compose logs -f homeassistant
```

### Check resource usage
```bash
docker stats
```

### Access services
- Glitch Cube API: http://raspberrypi.local:4567
- Home Assistant: http://raspberrypi.local:8123
- Portainer (if enabled): https://raspberrypi.local:9443

## Maintenance

### Update the application

Use the provided update script for safe updates:
```bash
bash scripts/update-raspi.sh
```

Or manually:
```bash
git pull
docker-compose pull
docker-compose build
docker-compose -f docker-compose.yml -f docker-compose.production.yml down
docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d
docker image prune -f  # Clean up old images
```

### Backup data
```bash
# Stop services
docker-compose down

# Backup data directories
tar -czf glitchcube-backup-$(date +%Y%m%d).tar.gz data/

# Restart services
docker-compose up -d
```

### Performance Tuning

For Raspberry Pi 5 optimization:
- The docker-compose.yml includes CPU and memory limits
- Adjust these based on your workload
- Monitor with `docker stats` and tune accordingly

## Troubleshooting

### Container won't start
```bash
# Check logs
docker-compose logs glitchcube

# Verify environment variables
docker-compose config

# Rebuild from scratch
docker-compose down -v
docker-compose build --no-cache
docker-compose up -d
```

### Home Assistant connection issues
- Verify HA_TOKEN is correct
- Check that Home Assistant is running: `docker-compose ps homeassistant`
- Test connection: `curl http://localhost:8123/api/`

### Out of memory
- Check swap: `free -h`
- Add swap if needed:
```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## License

[Your License Here]