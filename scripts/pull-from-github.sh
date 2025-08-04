#!/bin/bash
# Pull-from-github script - runs on Raspberry Pi to pull and deploy new commits
# Triggered by Home Assistant automation when GitHub notifies of new commits
# Flow: GitHub Action → HA API → HA Automation → This script
#
# Can also be run manually: ./scripts/pull-from-github.sh
# Or via rake task: rake deploy:pull

set -e

REPO_PATH="/home/eric/glitchcube"
LOG_FILE="/var/log/glitchcube-pull-deploy.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cd "$REPO_PATH"

# Get current commit for logging
CURRENT_COMMIT=$(git rev-parse HEAD)

# Optional: Check if there are actually new commits
# (Useful for manual runs or as a safety check)
git fetch origin main
REMOTE_COMMIT=$(git rev-parse origin/main)

if [ "$CURRENT_COMMIT" = "$REMOTE_COMMIT" ]; then
    log "Already up to date at commit: $CURRENT_COMMIT"
    # Still continue in case local files need updating
else
    log "New commits available: $CURRENT_COMMIT → $REMOTE_COMMIT"
fi

log "Starting deployment process..."
    
# Create deployment snapshot for rollback
mkdir -p deploy-snapshots
cp docker-compose.yml "deploy-snapshots/docker-compose-$(date +%Y%m%d-%H%M%S).yml"

# Keep only the most recent snapshot (oh shit or let it ride!)
ls -t deploy-snapshots/docker-compose-*.yml 2>/dev/null | tail -n +2 | xargs rm -f 2>/dev/null || true

# Pull latest changes
log "Pulling latest changes..."
git pull origin main

# Update Home Assistant config if needed
if [ -d 'config/homeassistant' ]; then
        log "Updating Home Assistant configuration..."
        if docker-compose ps | grep -q homeassistant; then
            docker exec glitchcube_homeassistant rm -f /config/configuration.yaml /config/scenes.yaml 2>/dev/null
            docker exec glitchcube_homeassistant rm -rf /config/automations /config/scripts /config/sensors /config/template /config/input_helpers 2>/dev/null
            docker cp config/homeassistant/. glitchcube_homeassistant:/config/ || { log "Failed to copy HA config!"; exit 1; }
            docker-compose restart homeassistant
    fi
fi

# Update custom components if needed
if [ -d 'homeassistant_components' ]; then
        log "Installing Home Assistant custom components..."
        mkdir -p data/production/homeassistant/custom_components
        sudo rm -rf data/production/homeassistant/custom_components/glitchcube_conversation 2>/dev/null
        cp -r homeassistant_components/* data/production/homeassistant/custom_components/
        
        if docker-compose ps | grep -q homeassistant; then
            for component in homeassistant_components/*/; do
                component_name=$(basename "$component")
                log "Installing component: $component_name"
                docker cp "$component" glitchcube_homeassistant:/config/custom_components/ || { log "Failed to copy component: $component_name"; exit 1; }
            done
            docker-compose restart homeassistant
    fi
fi

# Update Mosquitto config if needed
if [ -f 'config/mosquitto/mosquitto.conf' ]; then
        log "Updating Mosquitto configuration..."
        if docker-compose ps | grep -q mosquitto; then
            docker cp config/mosquitto/mosquitto.conf glitchcube_mosquitto:/mosquitto/config/mosquitto.conf || { log "Failed to copy Mosquitto config!"; exit 1; }
            docker-compose restart mosquitto
    fi
fi

# Rebuild and restart main application
log "Rebuilding application containers..."
docker-compose build glitchcube sidekiq
docker-compose up -d

# Tag this deployment as last-known-good
docker tag glitchcube:latest glitchcube:last-known-good

NEW_COMMIT=$(git rev-parse HEAD)
log "✅ Deployment complete! $CURRENT_COMMIT → $NEW_COMMIT"