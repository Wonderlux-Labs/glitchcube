#!/bin/bash

echo "🔧 Fixing containerd connection timeout issue..."
echo "================================================"

# Check containerd service status
echo "📊 Containerd service status:"
sudo systemctl status containerd --no-pager -l

echo ""
echo "🔍 Checking containerd socket:"
if [ -S /run/containerd/containerd.sock ]; then
    echo "✅ Containerd socket exists"
    ls -la /run/containerd/containerd.sock
    
    # Test socket connectivity
    echo ""
    echo "🧪 Testing containerd socket connectivity..."
    if timeout 5s ctr version >/dev/null 2>&1; then
        echo "✅ Containerd is responding via socket"
    else
        echo "❌ Containerd socket not responding"
        
        echo ""
        echo "🔍 Checking containerd processes:"
        ps aux | grep containerd | grep -v grep
        
        echo ""
        echo "📋 Recent containerd logs:"
        sudo journalctl -u containerd --no-pager -n 20
    fi
else
    echo "❌ Containerd socket missing at /run/containerd/containerd.sock"
fi

echo ""
echo "🛠️  Applying containerd fix..."

# Step 1: Stop Docker first (depends on containerd)
echo "1. Stopping Docker service..."
sudo systemctl stop docker.socket || true
sudo systemctl stop docker.service || true

# Step 2: Stop containerd
echo "2. Stopping containerd service..."
sudo systemctl stop containerd.service || true

# Step 3: Kill any stuck processes
echo "3. Cleaning up stuck processes..."
sudo pkill -f containerd || true
sudo pkill -f dockerd || true

# Step 4: Clean up runtime state
echo "4. Cleaning up runtime state..."
sudo rm -rf /run/containerd/containerd.sock || true
sudo rm -rf /run/containerd/containerd.pid || true
sudo rm -rf /var/run/docker.sock || true
sudo rm -rf /var/run/docker.pid || true

# Step 5: Start containerd first
echo "5. Starting containerd service..."
sudo systemctl start containerd.service

# Step 6: Wait for containerd to be ready
echo "6. Waiting for containerd to become ready..."
for i in {1..30}; do
    if [ -S /run/containerd/containerd.sock ] && timeout 3s ctr version >/dev/null 2>&1; then
        echo "✅ Containerd is ready (attempt $i)"
        break
    fi
    echo -n ". "
    sleep 1
done

if ! timeout 3s ctr version >/dev/null 2>&1; then
    echo ""
    echo "❌ Containerd failed to start properly"
    echo "📋 Containerd service status:"
    sudo systemctl status containerd --no-pager -l
    echo ""
    echo "📋 Recent containerd logs:"
    sudo journalctl -u containerd --no-pager -n 30
    exit 1
fi

echo ""
echo "7. Starting Docker service..."
sudo systemctl start docker.service

# Step 7: Wait for Docker to connect to containerd
echo "8. Waiting for Docker to connect to containerd..."
for i in {1..60}; do
    if timeout 5s docker version >/dev/null 2>&1; then
        echo ""
        echo "✅ Docker successfully connected to containerd (attempt $i)"
        
        # Test container functionality
        echo "🧪 Testing container functionality..."
        if timeout 30s docker run --rm hello-world >/dev/null 2>&1; then
            echo "✅ Container test successful!"
        else
            echo "⚠️  Container test failed, but daemon is responding"
        fi
        
        echo ""
        echo "✅ Fix complete - Docker is working!"
        exit 0
    fi
    
    # Show progress every 10 attempts
    if [ $((i % 10)) -eq 0 ]; then
        echo ""
        echo "Still waiting for Docker connection... (${i}s)"
        echo "Current Docker logs:"
        sudo journalctl -u docker --no-pager -n 5 --since "30 seconds ago"
    else
        echo -n ". "
    fi
    sleep 1
done

echo ""
echo "❌ Docker still not responding after 60 seconds"
echo ""
echo "📊 Final status check:"
echo "Containerd status:"
sudo systemctl is-active containerd || echo "Containerd not active"
echo "Docker status:"
sudo systemctl is-active docker || echo "Docker not active"

echo ""
echo "📋 Recent logs for troubleshooting:"
echo "=== Containerd logs ==="
sudo journalctl -u containerd --no-pager -n 10
echo ""
echo "=== Docker logs ==="
sudo journalctl -u docker --no-pager -n 10

echo ""
echo "💡 If issue persists, try:"
echo "1. Check system resources: free -h"
echo "2. Check disk space: df -h /var/lib/docker"
echo "3. Reboot system: sudo reboot"
echo "4. Check for kernel issues: dmesg | tail -20"