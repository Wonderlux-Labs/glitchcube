#!/bin/bash

# Official Pi 5 cgroup fix based on GitHub issue closed 1 hour ago
# https://github.com/raspberrypi/linux/issues/5933
# Solution from pelwell (Pi maintainer)

echo "🔧 Applying official Pi 5 cgroup fix (no DT change needed)..."

# Show current state
echo "🔍 Current kernel parameters:"
cat /proc/cmdline | tr ' ' '\n' | grep -E "(cgroup|memory)" || echo "No cgroup parameters found"

echo -e "\n🔍 Current cgroup v2 status:"
if [ -f /sys/fs/cgroup/cgroup.subtree_control ]; then
    echo "cgroup v2 controllers: $(cat /sys/fs/cgroup/cgroup.subtree_control)"
    if grep -q "memory" /sys/fs/cgroup/cgroup.subtree_control; then
        echo "✅ Memory cgroup is already working in cgroup v2!"
        echo "🐳 Testing Docker..."
        if timeout 10s docker run --rm hello-world >/dev/null 2>&1; then
            echo "✅ Docker is working!"
            exit 0
        else
            echo "❌ Docker still not working, continuing with fix..."
        fi
    else
        echo "❌ Memory cgroup not enabled"
    fi
else
    echo "❌ cgroup v2 not available"
fi

# Read current cmdline.txt
CURRENT_CMDLINE=$(cat /boot/firmware/cmdline.txt)
echo -e "\n📝 Current cmdline.txt:"
echo "$CURRENT_CMDLINE"

# According to pelwell: 
# 1. DTB has cgroup_disable=memory (this is intentional)
# 2. We just need cgroup_enable=memory in cmdline.txt
# 3. Order matters - cmdline.txt is processed AFTER DTB
# 4. No need for cgroup_memory=1

# Check if we already have the right parameter
if echo "$CURRENT_CMDLINE" | grep -q "cgroup_enable=memory"; then
    echo "✅ cgroup_enable=memory already present"
    
    # Remove cgroup_memory=1 if present (not needed according to maintainer)
    if echo "$CURRENT_CMDLINE" | grep -q "cgroup_memory=1"; then
        echo "🧹 Removing unnecessary cgroup_memory=1 parameter..."
        NEW_CMDLINE=$(echo "$CURRENT_CMDLINE" | sed 's/ cgroup_memory=1//g')
        
        # Backup and update
        sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.backup-$(date +%s)
        echo "$NEW_CMDLINE" | sudo tee /boot/firmware/cmdline.txt
        echo "✅ Cleaned up cmdline.txt"
    fi
else
    echo "📝 Adding cgroup_enable=memory to cmdline.txt..."
    
    # Add just cgroup_enable=memory (official solution)
    NEW_CMDLINE="$CURRENT_CMDLINE cgroup_enable=memory"
    
    # Backup and update
    sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.backup-$(date +%s)
    echo "$NEW_CMDLINE" | sudo tee /boot/firmware/cmdline.txt
    
    echo "✅ Added cgroup_enable=memory to cmdline.txt"
fi

# Show the final cmdline.txt
echo -e "\n📝 Updated cmdline.txt:"
cat /boot/firmware/cmdline.txt

# Clean up Docker daemon.json if it exists (we may not need the workaround)
if [ -f /etc/docker/daemon.json ]; then
    echo -e "\n🧹 Backing up Docker daemon.json (may not be needed with proper cgroups)..."
    sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup-$(date +%s)
fi

echo -e "\n🔄 Expected behavior after reboot:"
echo "1. DTB will set: cgroup_disable=memory"
echo "2. cmdline.txt will override with: cgroup_enable=memory"
echo "3. Result: Memory cgroup enabled in cgroup v2"
echo "4. Docker should work without warnings"

echo -e "\n💡 Key insight from Pi maintainer:"
echo "- Pi 5 uses cgroup v2 (not the old v1 API in /proc/cgroups)"
echo "- Memory cgroup disabled by default to save resources"
echo "- cgroup_enable=memory in cmdline.txt overrides DTB setting"
echo "- No cgroup_memory=1 needed"

read -p "🔄 Reboot now to apply the official fix? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Rebooting to apply official Pi 5 cgroup fix..."
    sudo reboot
else
    echo "💡 Run 'sudo reboot' when ready to test the fix"
fi