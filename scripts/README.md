# GlitchCube Scripts Directory

Scripts are now organized into logical categories for better maintainability and clarity.

## Directory Structure

### 🚀 `deploy/` - Deployment Scripts
Scripts for deploying code to production environments:
- **`mac_deploy.sh`** - Mac Mini deployment (pulls latest code, restarts services)
- **`install_on_production.sh`** - Production installation script
- **`deploy_hass_config.sh`** - Deploy Home Assistant configuration

### 🛠️ `dev/` - Development Utilities
Scripts used during development and setup:
- **`generate_playa_zones.rb`** - Generate Burning Man playa zone data
- **`download_bm2025_data.rb`** - Download Burning Man 2025 data
- **`cleanup_ha_config.rb`** - Clean up Home Assistant configuration
- **`ha_schema_sync.rb`** - Sync Home Assistant schemas

### 🖥️ `prod/` - Production Management
Scripts for managing the production Mac Mini system:
- **`mac_mini_startup.sh`** - Main startup script for Mac Mini
- **`glitchcube_restart.sh`** - Restart GlitchCube services
- **`glitchcube_monitor.sh`** - Monitor system health
- **`check_mac_mini_health.sh`** - Health check script
- **`push_health_to_uptime_kuma.sh`** - Send health metrics to monitoring
- **`starlink_grpc_check.sh`** - Check Starlink connectivity
- **`install_mac_mini_startup.sh`** - Install startup services
- **`com.glitchcube.startup.plist`** - macOS LaunchAgent configuration

### 🔧 `maintenance/` - Backup & Maintenance
Scripts for system maintenance and data management:
- **`backup-data.sh`** - Backup all persistent data
- **`restore-data.sh`** - Restore data from backup

### ⚙️ `utils/` - Utility Scripts
Shared utilities used by other scripts:
- **`common_config.sh`** - Shared configuration and functions
- **`update_ha_entities_doc.rb`** - Update Home Assistant entity documentation

## Quick Reference

### Essential Commands
```bash
# Backup before major changes
./scripts/maintenance/backup-data.sh

# Deploy latest code to Mac Mini
./scripts/deploy/mac_deploy.sh

# Check system health
./scripts/prod/check_mac_mini_health.sh

# Restart services
./scripts/prod/glitchcube_restart.sh
```

### Development Workflow
```bash
# Generate development data
./scripts/dev/download_bm2025_data.rb
./scripts/dev/generate_playa_zones.rb

# Clean up configurations
./scripts/dev/cleanup_ha_config.rb
```

## Docker Commands Reference

Instead of wrapper scripts, use Docker commands directly:

### Service Management
```bash
# View all services
docker-compose ps

# Restart all services
docker-compose restart

# Restart specific service
docker-compose restart homeassistant

# View logs
docker-compose logs -f
docker-compose logs -f glitchcube

# Stop everything
docker-compose down

# Start everything
docker-compose up -d
```

### Health Checks
```bash
# Check service health
curl http://localhost:4567/health      # Glitch Cube API
curl http://localhost:8123/api/        # Home Assistant

# View resource usage
docker stats
```

### Production Deployment
```bash
# Deploy with production settings
docker-compose up -d

# With PostgreSQL
docker-compose --profile postgres up -d
```

## Rake Tasks

For more complex operations, use rake tasks:

```bash
# List all available tasks
bundle exec rake -T

# Run health checks
bundle exec rake health:check

# Clean up old logs
bundle exec rake logs:cleanup
```

## Archive

The `archive/` directory contains old Docker debugging scripts that were used during Pi 5 setup issues. These are kept for reference but not needed for normal operation.