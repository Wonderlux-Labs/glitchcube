#!/bin/bash
# Deploy Home Assistant config from Mac Mini (git repo) to HA VM

set -e

GLITCHCUBE_DIR="/Users/eristmini/glitch/glitchcube"
HASS_CONFIG_SOURCE="$GLITCHCUBE_DIR/config/homeassistant"
HASS_HOST="root@glitch.local"
HASS_CONFIG_DEST="/config"
LOG_FILE="/Users/eristmini/glitch/deploy_hass.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "Deploying Home Assistant config"
log "========================================="

# Sync config files to Home Assistant
log "Syncing configuration files..."
rsync -av --delete \
    --exclude='.git' \
    --exclude='*.pyc' \
    --exclude='__pycache__' \
    --exclude='.storage' \
    --exclude='home-assistant.log' \
    --exclude='home-assistant_v2.db' \
    "$HASS_CONFIG_SOURCE/" "$HASS_HOST:$HASS_CONFIG_DEST/"

log "Config files synced"

# Check config validity
log "Checking Home Assistant configuration..."
ssh $HASS_HOST "ha core check" || {
    log "⚠️  Config check failed - not restarting"
    exit 1
}

# Restart Home Assistant
log "Restarting Home Assistant..."
ssh $HASS_HOST "ha core restart"

log "========================================="
log "Home Assistant deployment complete"
log "========================================="