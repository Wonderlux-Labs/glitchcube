# Glitch Cube Scripts

## Essential Scripts

### deploy.sh
Deploys code changes to the Glitch Cube device.
```bash
# Direct script usage
./scripts/deploy.sh "commit message"

# Or use rake tasks (recommended)
bundle exec rake deploy:push["commit message"]
bundle exec rake deploy:quick  # Auto-timestamps
```

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

### auto-deploy.sh
Automatically pulls and deploys new commits from GitHub. Used by systemd timer.
```bash
# Manual run
./scripts/auto-deploy.sh

# Setup automatic deployment (run once on device)
sudo cp scripts/glitchcube-auto-deploy.service /etc/systemd/system/
sudo cp scripts/glitchcube-auto-deploy.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable glitchcube-auto-deploy.timer
sudo systemctl start glitchcube-auto-deploy.timer

# Check status
sudo systemctl status glitchcube-auto-deploy.timer
sudo journalctl -u glitchcube-auto-deploy.service -f
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