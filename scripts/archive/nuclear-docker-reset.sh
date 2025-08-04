#!/bin/bash

# Nuclear Docker reset for completely hung Docker daemon
# Usage: ./scripts/nuclear-docker-reset.sh

echo "☢️  Nuclear Docker reset - this will force-kill everything..."

# Force kill all Docker-related processes
echo "💀 Force killing all Docker processes..."
sudo pkill -9 dockerd || true
sudo pkill -9 containerd || true
sudo pkill -9 containerd-shim || true
sudo pkill -9 runc || true
sudo pkill -9 docker-proxy || true

# Wait a moment
sleep 3

# Remove all Docker runtime files
echo "🧹 Removing all Docker runtime files..."
sudo rm -rf /var/run/docker*
sudo rm -rf /run/docker*
sudo rm -rf /run/containerd*
sudo rm -rf /var/lib/docker/runtimes
sudo rm -rf /var/lib/docker/tmp

# Stop the services completely
echo "⏹️  Stopping Docker services..."
sudo systemctl stop docker.service || true
sudo systemctl stop docker.socket || true
sudo systemctl stop containerd.service || true

# Kill any remaining processes
sudo pkill -9 -f docker || true
sudo pkill -9 -f containerd || true

# Clear systemd state
echo "🔄 Resetting systemd state..."
sudo systemctl reset-failed docker.service || true
sudo systemctl reset-failed containerd.service || true

# Remove any Docker systemd overrides that might be causing issues
echo "🗑️  Removing Docker systemd overrides..."
sudo rm -rf /etc/systemd/system/docker.service.d/
sudo systemctl daemon-reload

# Check if any Docker processes are still running
echo "🔍 Checking for remaining Docker processes..."
if pgrep -f docker > /dev/null; then
    echo "⚠️  Still some Docker processes running:"
    ps aux | grep -E "(docker|containerd)" | grep -v grep
    echo "💀 Force killing remaining processes..."
    sudo pkill -9 -f docker
    sudo pkill -9 -f containerd
fi

# Try to start Docker fresh
echo "🐳 Starting Docker fresh..."
sudo systemctl start docker.service

# Wait and check
echo "⏳ Waiting 10 seconds for Docker to start..."
sleep 10

# Test if Docker is responding
echo "🧪 Testing Docker..."
if timeout 15s docker version > /dev/null 2>&1; then
    echo "✅ Docker is working!"
    docker version
else
    echo "❌ Docker still not responding"
    echo "📊 Docker service status:"
    sudo systemctl status docker.service --no-pager -l
    echo ""
    echo "🔧 Last resort options:"
    echo "1. Reboot the entire system: sudo reboot"
    echo "2. Reinstall Docker completely:"
    echo "   sudo apt remove --purge docker-ce docker-ce-cli containerd.io"
    echo "   sudo apt autoremove"
    echo "   sudo apt update"
    echo "   sudo apt install docker-ce docker-ce-cli containerd.io"
fi