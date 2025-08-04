#!/bin/bash

# Fix Docker runtime errors on Raspberry Pi
# Usage: ./scripts/fix-docker-runtime.sh

set -e

echo "🔧 Fixing Docker runtime issues on Raspberry Pi..."

# Stop all containers
echo "⏹️  Stopping all containers..."
docker stop $(docker ps -aq) 2>/dev/null || true

# Remove all containers
echo "🗑️  Removing all containers..."
docker rm $(docker ps -aq) 2>/dev/null || true

# Clean up Docker system
echo "🧹 Cleaning Docker system..."
docker system prune -af --volumes

# Restart Docker daemon
echo "🔄 Restarting Docker daemon..."
sudo systemctl restart docker

# Wait for Docker to be ready
echo "⏳ Waiting for Docker to be ready..."
sleep 10

# Check Docker status
echo "✅ Checking Docker status..."
docker version
docker info | grep "Storage Driver"

# Create necessary directories
echo "📁 Creating necessary directories..."
mkdir -p ./data/mosquitto/{config,data,log}
mkdir -p ./data/esphome
mkdir -p ./data/music-assistant
mkdir -p ./data/configurator

# Set proper permissions
echo "🔐 Setting proper permissions..."
sudo chown -R eric:eric ./data/

echo "🎉 Docker runtime fix complete! You can now run docker-compose up"