# Volume Safety Review - Docker Prune Protection

## Named Volumes (Protected from `docker system prune`)
These volumes will NOT be deleted by `docker system prune` unless you use the `--volumes` flag:

1. **glitchcube_data** - Main app data (development only)
2. **homeassistant_config** - HA configuration (development only)
3. **portainer_data** - Portainer settings
4. **mosquitto_data** - MQTT broker persistent data
5. **mosquitto_logs** - MQTT logs
6. **esphome_config** - ESPHome device configurations
7. **music_assistant_data** - Music Assistant settings

## Bind Mounts (Always Safe)
These are directories on your host machine and are never affected by Docker prune:

### Always Used (Dev & Production)
- `./logs:/app/logs` - Application logs
- `./docs/context:/app/data/context_documents:ro` - Context documents (read-only)
- `./config/mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro` - MQTT config
- `/etc/localtime:/etc/localtime:ro` - System time
- `/run/dbus:/run/dbus:ro` - System D-Bus
- `/var/run/docker.sock:/var/run/docker.sock` - Docker socket for Portainer/Glances

### Production Bind Mounts (via environment variables)
- `${HA_CONFIG_PATH:-./data/production/homeassistant}:/config` - Defaults to production
- `${GLITCHCUBE_DATA_PATH:-./data/production/glitchcube}:/app/data` - Defaults to production
- `./data/redis:/data` - Redis persistence (always bind mount)
- `./data/production/postgres:/var/lib/postgresql/data` - PostgreSQL (when used)

## Safety Analysis

### ✅ SAFE from `docker system prune`:
- All bind mounts (./logs, ./docs/context, ./data/*)
- All named volumes (unless --volumes flag is used)

### ⚠️ VULNERABLE to `docker volume prune` or `docker system prune --volumes`:
- glitchcube_data (development data)
- homeassistant_config (development HA config)
- All other named volumes

### 🛡️ Production Data Protection:
Production uses bind mounts by default, so data is stored in:
- `./data/production/homeassistant/` - HA config and data
- `./data/production/glitchcube/` - App data and SQLite DB
- `./data/redis/` - Redis persistence
- `./logs/` - All application logs

## Recommendations

1. **For Development**: 
   - Use `docker system prune` (without --volumes) safely
   - Be careful with `docker volume prune`
   - Consider periodic backups of named volumes

2. **For Production**:
   - All critical data is in bind mounts under `./data/production/`
   - Safe to use any Docker prune commands
   - Backup strategy: Simply backup the `./data/production/` directory

3. **Switching Between Dev/Production**:
   ```bash
   # Development (uses named volumes)
   docker-compose up -d
   
   # Production (uses bind mounts)
   docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d
   
   # Or use environment variables to force production paths in dev
   export HA_CONFIG_PATH=./data/production/homeassistant
   export GLITCHCUBE_DATA_PATH=./data/production/glitchcube
   docker-compose up -d
   ```

## Volume Cleanup Commands (Use Carefully)

```bash
# Safe - removes unused containers, networks, images
docker system prune

# Safe - removes unused images including intermediate layers
docker system prune -a

# DANGEROUS - also removes unused volumes
docker system prune --volumes

# List volumes to see what would be removed
docker volume ls
docker volume ls -f dangling=true
```