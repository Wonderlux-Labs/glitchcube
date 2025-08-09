#!/bin/bash
# Deploy Home Assistant config from Mac Mini (git repo) to HA VM

set -e

# Source common configuration
source "$(dirname "$0")/common_config.sh"

HASS_CONFIG_SOURCE="$GLITCHCUBE_DIR/config/homeassistant"
HASS_CONFIG_DEST="/config"
LOG_FILE="$LOG_DIR/deploy_hass.log"

# Use the current reachable host
HASS_CONNECT="${HASS_USER}@${CURRENT_HASS_HOST}"

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
    "$HASS_CONFIG_SOURCE/" "$HASS_CONNECT:$HASS_CONFIG_DEST/"

log "Config files synced"

# Check config validity
log "Checking Home Assistant configuration..."
ssh $HASS_CONNECT "ha core check" || {
    log "⚠️  Config check failed - not restarting"
    exit 1
}

# Restart Home Assistant
log "Restarting Home Assistant..."
ssh $HASS_CONNECT "ha core restart"

log "========================================="
log "Home Assistant deployment complete"
log "========================================="