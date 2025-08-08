# Glitch Cube Scripts

## Essential Scripts

### Testing Scripts
Development and debugging scripts are organized in `testing_scripts/`. See [testing_scripts/README.md](testing_scripts/README.md) for details.

### Deployment Scripts
All deployment scripts have been moved to the `deploy/` subdirectory. See [deploy/README.md](deploy/README.md) for details.

- **Mac mini VM deployment**: `deploy/vm-update-ha-config.sh`
- **Raspberry Pi deployment**: `deploy/pull-from-github.sh`
- **Manual deployment**: `deploy/push-to-production.sh`

### backup-data.sh
Backs up all persistent data before major changes.
```bash
./scripts/backup-data.sh
```

### restore-data.sh
Restores data from a backup.
```bash
./scripts/restore-data.sh backup-20240101-120000.tar.gz
```

### Automatic Deployment
For automatic deployment setup, see the scripts in `deploy/` directory:
- Systemd files: `deploy/glitchcube-auto-deploy.service` and `.timer`
- Setup instructions: [deploy/README.md](deploy/README.md)

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