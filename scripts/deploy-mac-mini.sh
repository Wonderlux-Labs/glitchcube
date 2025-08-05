#!/bin/bash
# Deploy script for Mac mini (VM + bare metal setup)

set -e

REPO_PATH="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="/var/log/glitchcube-deploy.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cd "$REPO_PATH"

# 1. Pull latest changes
log "Pulling latest changes..."
git pull origin main

# 2. Update Home Assistant config in VM (via shared folder)
# Assuming /Users/Shared/glitchcube-ha is mounted in VM as /config
if [ -d 'config/homeassistant' ]; then
    log "Updating Home Assistant configuration..."
    rsync -av --delete config/homeassistant/ /Users/Shared/glitchcube-ha/
    
    # Trigger HA reload via REST API
    curl -X POST \
        -H "Authorization: Bearer $HA_TOKEN" \
        -H "Content-Type: application/json" \
        http://homeassistant.local:8123/api/services/homeassistant/reload_all
fi

# 3. Update custom components
if [ -d 'homeassistant_components' ]; then
    log "Installing Home Assistant custom components..."
    rsync -av homeassistant_components/ /Users/Shared/glitchcube-ha/custom_components/
fi

# 4. Restart Sinatra app (running on host)
log "Restarting Sinatra application..."
# If using launchd
launchctl unload ~/Library/LaunchAgents/com.glitchcube.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.glitchcube.plist

# Or if running with a process manager like pm2
# pm2 restart glitchcube

log "✅ Deployment complete!"