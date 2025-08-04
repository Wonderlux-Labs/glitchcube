#!/bin/bash

# Fix Pi 5 cgroup memory issue - known Bookworm bug
# Based on: https://forums.raspberrypi.com/viewtopic.php?t=389843

echo "🔧 Fixing Pi 5 cgroup memory issue (Bookworm bug)..."

# Check if we're on Pi 5
if [ -f /proc/device-tree/model ]; then
    MODEL=$(cat /proc/device-tree/model)
    echo "🔍 Detected: $MODEL"
fi

# Show current issue
echo "🐧 Current conflicting parameters:"
cat /proc/cmdline | tr ' ' '\n' | grep -E "(cgroup|memory)" || echo "No cgroup parameters found"

# Method 1: Update device tree blob to remove cgroup_disable=memory
echo -e "\n🛠️  Method 1: Checking device tree blob..."

# Find the DTB file for Pi 5
DTB_FILE="/boot/firmware/bcm2712-rpi-5-b.dtb"
if [ -f "$DTB_FILE" ]; then
    echo "✅ Found Pi 5 DTB file: $DTB_FILE"
    
    # Backup the DTB
    sudo cp "$DTB_FILE" "${DTB_FILE}.backup-$(date +%s)"
    echo "✅ Backed up DTB file"
    
    # Check if dtb has the problematic bootargs
    echo "🔍 Checking DTB for cgroup_disable=memory..."
    
    # Use dtc if available to examine the DTB
    if command -v dtc &> /dev/null; then
        if dtc -I dtb -O dts "$DTB_FILE" 2>/dev/null | grep -q "cgroup_disable=memory"; then
            echo "⚠️  Found cgroup_disable=memory in DTB - this needs manual fixing"
            echo "📝 Consider upgrading Pi OS or kernel with: sudo rpi-update"
        else
            echo "✅ DTB looks clean"
        fi
    else
        echo "⚠️  dtc not available, can't check DTB contents"
    fi
else
    echo "❌ Pi 5 DTB file not found"
fi

# Method 2: Try kernel parameter override
echo -e "\n🛠️  Method 2: Strong kernel parameter override..."

# Read current cmdline.txt
CURRENT_CMDLINE=$(cat /boot/firmware/cmdline.txt)
echo "Current cmdline.txt: $CURRENT_CMDLINE"

# Check if we already have the parameters
if echo "$CURRENT_CMDLINE" | grep -q "cgroup_enable=memory"; then
    echo "✅ cgroup_enable=memory already present"
else
    echo "📝 Adding strong cgroup override parameters..."
    
    # Add stronger cgroup parameters
    NEW_CMDLINE="$CURRENT_CMDLINE systemd.unified_cgroup_hierarchy=0 cgroup_enable=memory cgroup_memory=1"
    
    # Backup and update
    sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.backup-$(date +%s)
    echo "$NEW_CMDLINE" | sudo tee /boot/firmware/cmdline.txt
    
    echo "✅ Updated cmdline.txt with stronger cgroup parameters"
fi

# Method 3: Docker daemon configuration to work around the issue
echo -e "\n🛠️  Method 3: Configure Docker to work with limited cgroups..."

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
  "cgroup-parent": "docker.slice"
}
EOF

echo "✅ Created Docker daemon configuration"

echo -e "\n🔄 Next steps:"
echo "1. Reboot the system: sudo reboot"
echo "2. After reboot, check: cat /proc/cmdline | grep cgroup"
echo "3. Check cgroups: cat /proc/cgroups | grep memory"
echo "4. Test Docker: docker run --rm hello-world"
echo ""
echo "💡 If still not working after reboot:"
echo "   - Run 'sudo rpi-update' to get latest kernel"
echo "   - Consider using Docker without memory cgroups (less optimal but works)"

read -p "🔄 Reboot now to apply changes? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo reboot
fi