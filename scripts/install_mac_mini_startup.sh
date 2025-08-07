#!/bin/bash

# Install script for Mac Mini startup service
# Run this once to set up automatic startup on boot

set -e

# Configuration
REMOTE_HOST="eristmini@speedygonzo"
REMOTE_DIR="/Users/eristmini/glitch/glitchcube"
LOCAL_DIR="$(dirname "$0")"

echo "========================================="
echo "Glitch Cube Mac Mini Startup Installer"
echo "========================================="

# 1. Make startup script executable
echo "Making startup script executable..."
chmod +x "$LOCAL_DIR/mac_mini_startup.sh"

# 2. Copy files to Mac Mini
echo "Copying files to Mac Mini..."
scp "$LOCAL_DIR/mac_mini_startup.sh" "$REMOTE_HOST:$REMOTE_DIR/scripts/"
scp "$LOCAL_DIR/com.glitchcube.startup.plist" "$REMOTE_HOST:$REMOTE_DIR/scripts/"

# 3. Install on Mac Mini
echo "Installing startup service on Mac Mini..."
ssh "$REMOTE_HOST" << 'ENDSSH'
    # Make script executable
    chmod +x /Users/eristmini/glitch/glitchcube/scripts/mac_mini_startup.sh
    
    # Create logs directory if it doesn't exist
    mkdir -p /Users/eristmini/glitch/glitchcube/logs
    
    # Copy plist to LaunchAgents (runs as user, not root)
    cp /Users/eristmini/glitch/glitchcube/scripts/com.glitchcube.startup.plist ~/Library/LaunchAgents/
    
    # Load the service
    launchctl unload ~/Library/LaunchAgents/com.glitchcube.startup.plist 2>/dev/null || true
    launchctl load ~/Library/LaunchAgents/com.glitchcube.startup.plist
    
    echo "✅ Startup service installed successfully"
    echo ""
    echo "The service will:"
    echo "  - Run at system startup"
    echo "  - Check and start Redis"
    echo "  - Check and start PostgreSQL"
    echo "  - Start VMware Fusion and Home Assistant VM"
    echo "  - Wait for Home Assistant to be ready"
    echo "  - Start Glitch Cube application with foreman"
    echo ""
    echo "Logs will be written to:"
    echo "  - /Users/eristmini/glitch/startup.log"
    echo "  - /Users/eristmini/glitch/startup_stdout.log"
    echo "  - /Users/eristmini/glitch/startup_stderr.log"
    echo ""
    echo "To manually run the startup sequence:"
    echo "  /Users/eristmini/glitch/glitchcube/scripts/mac_mini_startup.sh"
    echo ""
    echo "To check service status:"
    echo "  launchctl list | grep glitchcube"
    echo ""
    echo "To stop the service:"
    echo "  launchctl unload ~/Library/LaunchAgents/com.glitchcube.startup.plist"
    echo ""
    echo "To start the service:"
    echo "  launchctl load ~/Library/LaunchAgents/com.glitchcube.startup.plist"
ENDSSH

echo "========================================="
echo "Installation complete!"
echo "========================================="