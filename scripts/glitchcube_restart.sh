#!/bin/bash

# Glitch Cube Restart/Recovery Script
# LESSON LEARNED: Since we have reliable startup script, just reboot for guaranteed clean state

# Configuration
GLITCHCUBE_DIR="/Users/eristmini/glitch/glitchcube"
LOG_FILE="/Users/eristmini/glitch/restart.log"
RESTART_REASON="${1:-manual}"

# Load SUDO_PASS from .env file
if [ -f "$GLITCHCUBE_DIR/.env" ]; then
    export $(grep SUDO_PASS "$GLITCHCUBE_DIR/.env" | xargs)
fi

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RESTART] $1" | tee -a "$LOG_FILE"
}

log "Reason: $RESTART_REASON"
log "Rebooting system for clean restart..."

# Reboot the system using SUDO_PASS
echo "$SUDO_PASS" | sudo -S shutdown -r now