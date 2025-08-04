# Glitch Cube Scripts

## Core Scripts

### Deployment & Updates
- **`deploy.sh`** - Main deployment script (commits, pushes, deploys to glitchcube.local with HA components)
- **`deploy-raspi.sh`** - Full Raspberry Pi setup script for new installations

### Maintenance
- **`backup-data.sh`** - Backup application data and configurations
- **`restore-data.sh`** - Restore from backup
- **`health-check.sh`** - System health monitoring
- **`status-check.sh`** - Check service status across all containers
- **`restart-services.sh`** - Restart all services
- **`rollback-glitchcube.sh`** - Rollback to previous version

### Development
- **`test_beacon.rb`** - Test beacon service functionality
- **`debug/`** - Debug utilities and test scripts

## Usage

### Quick Deploy
```bash
./scripts/deploy.sh "your commit message"
```

### Health Check
```bash
./scripts/health-check.sh
```

### Service Status
```bash
./scripts/status-check.sh
```

## Archive

The `archive/` directory contains old Docker debugging scripts that were used during Pi 5 setup issues. These are kept for reference but not needed for normal operation.