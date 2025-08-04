#!/bin/bash

# Diagnose Docker hanging issues on Raspberry Pi
# Usage: ./scripts/diagnose-docker-hang.sh

echo "🔍 Diagnosing Docker hanging issue..."

# Check if Docker service is running
echo "🐳 Docker service status:"
sudo systemctl status docker --no-pager -l

echo -e "\n📊 Docker daemon logs (last 50 lines):"
sudo journalctl -u docker.service -n 50 --no-pager

echo -e "\n🧠 Memory and swap status:"
free -h

echo -e "\n💾 Disk space:"
df -h

echo -e "\n🐧 Kernel boot parameters:"
cat /proc/cmdline

echo -e "\n⚙️  CGroup status:"
if [ -f /proc/cgroups ]; then
    echo "Available cgroups:"
    cat /proc/cgroups
else
    echo "❌ /proc/cgroups not found"
fi

echo -e "\n🔧 CGroup memory controller:"
if [ -f /sys/fs/cgroup/memory/memory.stat ]; then
    echo "✅ Memory cgroup is available"
else
    echo "❌ Memory cgroup not available - check kernel parameters"
fi

echo -e "\n🏃 Running processes (Docker related):"
ps aux | grep -E "(docker|containerd|runc)" | grep -v grep

echo -e "\n🌡️  System temperature:"
if command -v vcgencmd &> /dev/null; then
    vcgencmd measure_temp
else
    echo "vcgencmd not available"
fi

echo -e "\n🔌 Docker daemon socket:"
if [ -S /var/run/docker.sock ]; then
    echo "✅ Docker socket exists"
    ls -la /var/run/docker.sock
else
    echo "❌ Docker socket missing"
fi

echo -e "\n📡 Can we connect to Docker daemon?"
timeout 10s docker version || echo "❌ Docker daemon not responding (timeout after 10s)"

echo -e "\n🛠️  Suggested fixes:"
echo "1. If cgroups error: Remove 'cgroup_enable=memory cgroup_memory=1' from /boot/firmware/cmdline.txt"
echo "2. If memory issues: Check if swap is working properly"
echo "3. If hung processes: sudo systemctl restart docker"
echo "4. If persistent: Revert kernel parameters and reboot"