#!/bin/bash

echo "🚨 Fixing containerd crash (Illegal Instruction) on Pi 5..."
echo "========================================================"

echo "🔍 Current system info:"
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -r)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"

echo ""
echo "🔍 Current containerd info:"
if [ -f /usr/bin/containerd ]; then
    echo "Binary exists: $(file /usr/bin/containerd)"
    echo "Package info:"
    dpkg -l | grep containerd || echo "No containerd packages found"
else
    echo "❌ containerd binary not found"
fi

echo ""
echo "🛠️  Stopping services and fixing containerd..."

# Stop everything first
echo "1. Stopping Docker and containerd services..."
sudo systemctl stop docker.socket || true
sudo systemctl stop docker.service || true
sudo systemctl stop containerd.service || true

# Kill any lingering processes
sudo pkill -f dockerd || true
sudo pkill -f containerd || true

echo ""
echo "2. Removing potentially corrupted containerd..."
sudo apt-get remove --purge -y containerd.io containerd runc docker-ce docker-ce-cli || true

echo ""
echo "3. Cleaning up residual files..."
sudo rm -rf /usr/bin/containerd* || true
sudo rm -rf /usr/bin/ctr || true
sudo rm -rf /usr/bin/runc || true
sudo rm -rf /run/containerd || true
sudo rm -rf /var/lib/containerd || true

echo ""
echo "4. Updating package lists..."
sudo apt-get update

echo ""
echo "5. Installing Docker from official repository..."

# Add Docker's official GPG key and repository
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=arm64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

echo ""
echo "6. Installing compatible Docker and containerd for Pi 5..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ""
echo "7. Configuring Docker for Pi 5..."

# Create Docker daemon config optimized for Pi
sudo mkdir -p /etc/docker
cat << 'EOF' | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF

echo ""
echo "8. Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl enable docker

echo ""
echo "9. Testing containerd..."
sudo systemctl start containerd

# Wait for containerd to start
for i in {1..10}; do
    if sudo systemctl is-active --quiet containerd; then
        echo "✅ containerd is active (attempt $i)"
        break
    fi
    echo "Waiting for containerd... ($i/10)"
    sleep 2
done

if ! sudo systemctl is-active --quiet containerd; then
    echo "❌ containerd failed to start"
    echo "📋 containerd status:"
    sudo systemctl status containerd --no-pager -l
    echo ""
    echo "📋 containerd logs:"
    sudo journalctl -u containerd --no-pager -n 20
    exit 1
fi

# Test containerd functionality
echo "🧪 Testing containerd functionality..."
if sudo ctr version >/dev/null 2>&1; then
    echo "✅ containerd is responding to commands"
else
    echo "⚠️  containerd not responding to ctr commands"
fi

echo ""
echo "10. Starting Docker..."
sudo systemctl start docker

# Wait for Docker to connect to containerd
echo "🔗 Waiting for Docker to connect to containerd..."
for i in {1..30}; do
    if timeout 5s docker version >/dev/null 2>&1; then
        echo "✅ Docker successfully connected! (attempt $i)"
        break
    fi
    echo -n ". "
    sleep 2
done

echo ""
if timeout 5s docker version >/dev/null 2>&1; then
    echo "✅ Docker is working!"
    
    # Final test with container
    echo "🧪 Testing container functionality..."
    if timeout 30s docker run --rm hello-world; then
        echo ""
        echo "🎉 SUCCESS! Docker is fully functional on Pi 5"
    else
        echo "⚠️  Container test failed, but daemon is responding"
    fi
else
    echo "❌ Docker still not responding"
    echo ""
    echo "📊 Service status:"
    echo "Containerd: $(sudo systemctl is-active containerd)"
    echo "Docker: $(sudo systemctl is-active docker)"
    
    echo ""
    echo "📋 Recent Docker logs:"
    sudo journalctl -u docker --no-pager -n 10
fi

echo ""
echo "📋 Final system status:"
echo "Containerd version: $(sudo ctr version --client | head -1)"
echo "Docker version: $(docker --version)"

echo ""
echo "💡 If issues persist:"
echo "1. Check kernel compatibility: uname -r"
echo "2. Try rebooting: sudo reboot"
echo "3. Check for hardware issues: dmesg | grep -i error"