#!/bin/bash

# Fix Docker hanging after cgroup changes
# Usage: ./scripts/fix-docker-hang.sh

echo "🔧 Fixing Docker hanging issue..."

# Force stop Docker if it's hung
echo "⏹️  Force stopping Docker..."
sudo systemctl stop docker || true
sudo killall dockerd || true
sudo killall containerd || true

# Clear any stuck processes
echo "💀 Clearing stuck processes..."
sudo pkill -f docker || true
sudo pkill -f containerd || true
sudo pkill -f runc || true

# Remove Docker runtime state
echo "🧹 Clearing Docker runtime state..."
sudo rm -rf /var/run/docker.pid
sudo rm -rf /var/run/docker
sudo rm -rf /run/containerd

# Check current cmdline.txt
echo "🐧 Current kernel parameters:"
cat /proc/cmdline

# Offer to disable problematic cgroup settings
echo -e "\n🔄 If Docker continues to hang, the cgroup parameters might be incompatible."
echo "Current cmdline.txt:"
cat /boot/firmware/cmdline.txt

read -p "🚨 Remove cgroup parameters from cmdline.txt? This might fix the hanging. (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📝 Backing up and modifying cmdline.txt..."
    sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.bak-$(date +%s)
    
    # Remove cgroup parameters
    sudo sed -i 's/ cgroup_enable=memory cgroup_memory=1//g' /boot/firmware/cmdline.txt
    
    echo "✅ Removed cgroup parameters. Original backed up."
    echo "New cmdline.txt:"
    cat /boot/firmware/cmdline.txt
    
    echo "🔄 Reboot required to apply changes: sudo reboot"
    
    read -p "Reboot now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo reboot
    fi
else
    echo "🐳 Attempting to restart Docker with current settings..."
    sudo systemctl start docker
    
    echo "⏳ Waiting for Docker to respond..."
    for i in {1..10}; do
        if timeout 5s docker version >/dev/null 2>&1; then
            echo "✅ Docker is responding!"
            break
        fi
        echo -n "."
        sleep 2
    done
    
    if ! timeout 5s docker version >/dev/null 2>&1; then
        echo -e "\n❌ Docker still not responding."
        echo "💡 Consider running this script again and removing cgroup parameters."
    fi
fi