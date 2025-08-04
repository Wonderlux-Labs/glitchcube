# Data and Volume Management

## Directory Structure

```
glitchcube/
├── config/           # Configuration files (tracked in git)
│   └── mosquitto/    # Mosquitto broker config
├── data/            # Runtime data (NOT in git, created by Docker)
│   ├── development/ # Development data (Docker volumes)
│   └── production/  # Production data (bind mounts)
├── docs/            # Documentation (tracked in git)
│   └── context/     # Context documents for AI
└── logs/            # Application logs (bind mounted, not in git)
```

## Volume Strategy

### Development (default docker-compose.yml)
- Uses Docker **named volumes** for data persistence
- Data stored in Docker's volume directory
- Survives container restarts but not `docker-compose down -v`
- Good for development where you want clean state on rebuild

### Production (docker-compose.production.yml)
- Uses **bind mounts** to `./data/production/`
- Data persisted directly on host filesystem
- Survives all Docker operations
- Easy to backup, inspect, and migrate

### Logs
- Always bind mounted to `./logs/` in both environments
- Accessible from host for debugging
- Excluded from git

## Usage

### Development
```bash
# Start with development volumes
docker-compose up -d

# Data stored in Docker volumes
docker volume ls | grep glitchcube
```

### Production
```bash
# Start with production bind mounts
docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d

# Data stored in ./data/production/
ls -la ./data/production/
```

## Backup

### Development
```bash
# Backup Docker volumes
docker run --rm -v glitchcube_data:/data -v $(pwd):/backup alpine tar czf /backup/dev-backup.tar.gz -C / data
```

### Production
```bash
# Simply backup the data directory
tar czf production-backup.tar.gz ./data/production/
```

## Important Notes

1. The `./data/` directory is completely excluded from git
2. Config files that need to be in containers are copied from `./config/`
3. Context documents are read-only mounted from `./docs/context/`
4. Each service has its own data subdirectory for organization
5. Production uses the same image as development, just different volume mounts