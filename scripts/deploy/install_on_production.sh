#!/bin/bash

# Simple installation script to run DIRECTLY on the production Mac Mini
# This assumes you've already copied the files to the production machine

set -e

echo "========================================="
echo "Installing Glitch Cube Startup Service"
echo "========================================="

# Make sure we're in the right directory
cd /Users/eristmini/glitch/glitchcube

# Make the startup script executable
echo "Making startup script executable..."
chmod +x scripts/mac_mini_startup.sh

# Create logs directory if needed
echo "Creating logs directory..."
mkdir -p /Users/eristmini/glitch/glitchcube/logs
mkdir -p /Users/eristmini/glitch

# Create LaunchAgents directory if it doesn't exist
echo "Creating LaunchAgents directory..."
mkdir -p ~/Library/LaunchAgents

# Copy plist to LaunchAgents
echo "Copying plist file..."
cp scripts/com.glitchcube.startup.plist ~/Library/LaunchAgents/

# Unload if already loaded (ignore errors)
echo "Unloading any existing service..."
launchctl unload ~/Library/LaunchAgents/com.glitchcube.startup.plist 2>/dev/null || true

# Load the service
echo "Loading the service..."
launchctl load ~/Library/LaunchAgents/com.glitchcube.startup.plist

echo "✅ Service installed successfully!"
echo ""
echo "To check if it's loaded:"
echo "  launchctl list | grep glitchcube"
echo ""
echo "To manually run the startup script:"
echo "  /Users/eristmini/glitch/glitchcube/scripts/mac_mini_startup.sh"