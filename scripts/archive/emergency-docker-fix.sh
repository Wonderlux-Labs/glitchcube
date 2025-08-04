#!/bin/bash

# Emergency Docker fix for Raspberry Pi runtime corruption
# Usage: ./scripts/emergency-docker-fix.sh

set -e

echo "🚨 Emergency Docker fix for runtime corruption on Raspberry Pi"
echo "This script will attempt to fix Docker by stopping it, cleaning its runtime state,"
echo "and ensuring the configuration is robust for a Pi environment."
echo

read -p "🚨 This will NOT delete your images or volumes. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
fi

# Check available memory and disk space
echo "💾 Checking system resources..."
free -h
df -h

# Check for kernel cgroup settings, crucial for Docker on Pi
echo "🐧 Checking kernel cgroup configuration..."
if ! grep -q "cgroup_enable=memory cgroup_memory=1" /boot/cmdline.txt; then
    echo "⚠️  WARNING: Kernel memory cgroup may not be enabled."
    echo "   This is a common cause of Docker instability on Raspberry Pi."
    echo "   Please consider adding 'cgroup_enable=memory cgroup_memory=1' to /boot/cmdline.txt and rebooting."
    sleep 5
fi

# Check for memory issues
echo "🧠 Checking for memory pressure..."
if [ -f /proc/pressure/memory ]; then
    echo "Memory pressure:"
    cat /proc/pressure/memory
fi

# Check swap space (Pi often needs more swap for Docker builds)
echo "💿 Checking swap space..."
SWAP_SIZE=$(free | grep Swap | awk '{print $2}')
if [ "$SWAP_SIZE" -lt 2000000 ]; then
    echo "⚠️  Low swap space detected. Consider increasing swap size."
    echo "   Current swap: $(($SWAP_SIZE / 1024))MB"
    echo "   Recommended: 2GB+ for Docker builds"
fi

# Stop Docker completely
echo "⏹️  Stopping Docker daemon completely..."
sudo systemctl stop docker
sudo systemctl stop docker.socket
sleep 5

# Kill any remaining Docker processes
echo "💀 Killing any remaining Docker processes..."
sudo pkill -f docker || true
sudo pkill -f containerd || true
sudo pkill -f runc || true

# Clean up Docker runtime directories by moving them as a backup
echo "🧹 Cleaning Docker runtime directories (backing up to .bak-TIMESTAMP)..."
TIMESTAMP=$(date +%s)
[ -d /var/lib/docker/runtimes ] && sudo mv /var/lib/docker/runtimes "/var/lib/docker/runtimes.bak-$TIMESTAMP"
[ -d /var/lib/docker/tmp ] && sudo mv /var/lib/docker/tmp "/var/lib/docker/tmp.bak-$TIMESTAMP"
sudo rm -rf /run/docker
sudo rm -rf /run/containerd

# Remove Docker lock files
echo "🔓 Removing Docker lock files..."
sudo rm -f /var/lib/docker/network/files/local-kv.db.lock
sudo rm -f /var/lib/docker/volumes/metadata.db.lock

# Set up proper systemd configuration for Docker
echo "⚙️  Applying robust systemd configuration for Docker..."
sudo mkdir -p /etc/systemd/system/docker.service.d
cat << EOF | sudo tee /etc/systemd/system/docker.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --storage-driver=overlay2 --log-driver=json-file --log-opt max-size=10m --log-opt max-file=3
Delegate=yes
TimeoutStartSec=0
EOF

# Reload systemd
echo "🔄 Reloading systemd..."
sudo systemctl daemon-reload

# Start Docker with clean state
echo "🐳 Starting Docker with clean state..."
sudo systemctl start docker

# Wait for Docker to be fully ready with proper polling
echo -n "⏳ Waiting for Docker to be fully ready..."
for i in {1..20}; do
    if docker info >/dev/null 2>&1; then
        echo "✅ Docker daemon is responsive."
        break
    fi
    echo -n "."
    sleep 2
done
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon did not start correctly. Check logs with 'journalctl -u docker.service'"
    exit 1
fi

# Test Docker with simple command
echo "🧪 Testing Docker with simple command..."
if docker run --rm hello-world; then
    echo "✅ Docker basic test passed"
else
    echo "❌ Docker basic test failed - may need system reboot"
    exit 1
fi

# Test Docker build capability with minimal Alpine
echo "🔨 Testing Docker build capability..."
cat << 'EOF' > /tmp/test-dockerfile
FROM alpine:latest
RUN echo "Test build successful"
EOF

if docker build -t test-build -f /tmp/test-dockerfile /tmp; then
    echo "✅ Docker build test passed"
    docker rmi test-build
    rm /tmp/test-dockerfile
else
    echo "❌ Docker build test failed"
    echo "🔧 The issue might be deeper. Possible next steps:"
    echo "   1. Reinstall Docker binaries: sudo apt-get install --reinstall docker-ce docker-ce-cli containerd.io"
    echo "   2. Reboot the Pi: sudo reboot"
    echo "   3. Check Pi power supply and temperature: vcgencmd measure_temp"
    echo "   4. Check SD card health: sudo dmesg | grep -i 'mmc\\|error\\|fail'"
    echo "   5. Increase swap space if it's low."
    exit 1
fi

echo "🎉 Docker emergency fix complete!"
echo "💡 You can now try to run your application: docker-compose up -d --build"