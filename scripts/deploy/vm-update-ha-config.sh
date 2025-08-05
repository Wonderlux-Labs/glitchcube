#!/bin/bash
# VM-based Home Assistant configuration updater
# This script runs INSIDE the Home Assistant VM
# It pulls from GitHub and updates the HA configuration

set -o errexit  # Exit on any error
set -o pipefail # Exit on error in a pipeline
set -o nounset  # Exit on unset variables

# Configuration
REPO_DIR="/home/homeassistant/glitchcube_repo"  # Separate repo clone for updates
CONFIG_DIR="/config"  # Home Assistant config directory in VM
LOG_FILE="/var/log/ha_config_updater.log"
LOCK_FILE="/tmp/ha_config_updater.lock"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# --- Locking ---
# Use flock to prevent concurrent update runs
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[$(date)] Update already in progress. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

# --- Logging ---
# Redirect all output to log file while still showing on console
exec &> >(tee -a "$LOG_FILE")

echo "=================================================="
echo "Starting HA config update at $(date)"
echo "=================================================="

# Ensure repo directory exists
if [ ! -d "$REPO_DIR" ]; then
    echo "ERROR: Repository not found at $REPO_DIR"
    echo "Please clone the repository first:"
    echo "  git clone https://github.com/YOUR_ORG/glitchcube.git $REPO_DIR"
    echo "This is a separate clone used only for pulling HA config updates"
    exit 1
fi

cd "$REPO_DIR"

# Fetch latest changes from remote without merging
echo "Fetching latest changes from GitHub..."
git fetch origin main

# Check if local is behind remote
LOCAL_COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git rev-parse origin/main)

if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
    echo "Configuration is already up-to-date."
    echo "Local commit: ${LOCAL_COMMIT:0:7}"
    exit 0
fi

echo "New commits detected!"
echo "  Current: ${LOCAL_COMMIT:0:7}"
echo "  Remote:  ${REMOTE_COMMIT:0:7}"

# Create backup of current config
BACKUP_DIR="$CONFIG_DIR/backups/$(date +%Y%m%d-%H%M%S)"
echo "Creating backup at $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
cp -r "$CONFIG_DIR"/*.yaml "$BACKUP_DIR/" 2>/dev/null || true
cp -r "$CONFIG_DIR"/automations "$BACKUP_DIR/" 2>/dev/null || true
cp -r "$CONFIG_DIR"/scripts "$BACKUP_DIR/" 2>/dev/null || true
cp -r "$CONFIG_DIR"/sensors "$BACKUP_DIR/" 2>/dev/null || true
cp -r "$CONFIG_DIR"/custom_components "$BACKUP_DIR/" 2>/dev/null || true

# Reset local state to match remote branch exactly
# This avoids merge conflicts but will discard local changes
echo "Pulling changes from GitHub..."
git reset --hard origin/main

echo "Copying Home Assistant configuration files..."
# Copy main config files
if [ -d "config/homeassistant" ]; then
    cp -v config/homeassistant/*.yaml "$CONFIG_DIR/" 2>/dev/null || true
    
    # Copy subdirectories
    for dir in automations scripts sensors template input_helpers; do
        if [ -d "config/homeassistant/$dir" ]; then
            echo "  Copying $dir/..."
            mkdir -p "$CONFIG_DIR/$dir"
            cp -r "config/homeassistant/$dir"/* "$CONFIG_DIR/$dir/" 2>/dev/null || true
        fi
    done
fi

# Copy custom components
if [ -d "homeassistant_components" ]; then
    echo "Installing custom components..."
    mkdir -p "$CONFIG_DIR/custom_components"
    for component in homeassistant_components/*/; do
        if [ -d "$component" ]; then
            component_name=$(basename "$component")
            echo "  Installing: $component_name"
            rm -rf "$CONFIG_DIR/custom_components/$component_name"
            cp -r "$component" "$CONFIG_DIR/custom_components/"
        fi
    done
fi

# Validate configuration
echo "Validating Home Assistant configuration..."
if command -v hass &> /dev/null; then
    # Direct HA installation
    if ! hass --script check_config -c "$CONFIG_DIR"; then
        echo "ERROR: Configuration validation failed!"
        echo "Restoring backup..."
        cp -r "$BACKUP_DIR"/* "$CONFIG_DIR/"
        exit 1
    fi
else
    echo "WARNING: Cannot validate config - hass command not found"
    echo "Proceeding with restart anyway..."
fi

# Clean up old backups (keep last 5)
echo "Cleaning up old backups..."
ls -t "$CONFIG_DIR/backups" 2>/dev/null | tail -n +6 | xargs -I {} rm -rf "$CONFIG_DIR/backups/{}" 2>/dev/null || true

# Restart Home Assistant
echo "Restarting Home Assistant..."
if command -v ha &> /dev/null; then
    # Home Assistant OS/Supervised
    ha core restart
elif systemctl is-active --quiet home-assistant@homeassistant; then
    # Systemd service
    sudo systemctl restart home-assistant@homeassistant
else
    echo "WARNING: Could not determine how to restart Home Assistant"
    echo "Please restart Home Assistant manually"
fi

# Record the update
echo "$REMOTE_COMMIT" > "$CONFIG_DIR/.last_deployed_commit"

echo "=================================================="
echo "Update completed successfully at $(date)"
echo "Deployed commit: ${REMOTE_COMMIT:0:7}"
echo "=================================================="