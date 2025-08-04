#!/bin/bash

# Fix Pi 5 cgroup memory issue - PARAMETER ORDER MATTERS
# Based on: https://github.com/raspberrypi/linux/issues/5933
# Key insight: cgroup_enable=memory must come AFTER cgroup_disable=memory

echo "🔧 Fixing Pi 5 cgroup parameter ordering issue..."
echo "📚 Solution: Ensure cgroup_enable=memory comes AFTER cgroup_disable=memory"

# Show current state
echo -e "\n🔍 Current kernel command line:"
cat /proc/cmdline | tr ' ' '\n' | grep -E "(cgroup|memory)" | nl

echo -e "\n🔍 Current cgroup v2 status:"
if [ -f /sys/fs/cgroup/cgroup.subtree_control ]; then
    echo "cgroup v2 controllers: $(cat /sys/fs/cgroup/cgroup.subtree_control)"
    if grep -q "memory" /sys/fs/cgroup/cgroup.subtree_control; then
        echo "✅ Memory cgroup is already working!"
        exit 0
    else
        echo "❌ Memory cgroup not enabled (this is the problem we're fixing)"
    fi
else
    echo "❌ cgroup v2 not available"
fi

# Read current cmdline.txt
CMDLINE_FILE="/boot/firmware/cmdline.txt"
CURRENT_CMDLINE=$(cat "$CMDLINE_FILE")
echo -e "\n📝 Current cmdline.txt:"
echo "$CURRENT_CMDLINE"

# Check the problematic pattern: cgroup_enable comes before cgroup_disable
if echo "$CURRENT_CMDLINE" | grep -E "cgroup_enable.*cgroup_disable"; then
    echo -e "\n❌ PROBLEM FOUND: cgroup_enable comes BEFORE cgroup_disable"
    echo "   This causes cgroup_disable to override cgroup_enable"
    echo "   We need to fix the parameter order!"
elif echo "$CURRENT_CMDLINE" | grep -q "cgroup_disable.*cgroup_enable"; then
    echo -e "\n✅ Parameter order looks correct"
    echo "   But memory cgroup still not working - adding missing parameter"
else
    echo -e "\n🔍 Analyzing current parameters..."
fi

# Create the correct command line
echo -e "\n🛠️  Creating corrected cmdline.txt..."

# Start with current cmdline and remove ALL cgroup parameters
CLEAN_CMDLINE=$(echo "$CURRENT_CMDLINE" | sed -E 's/\s*(cgroup_[^[:space:]]*|systemd\.unified_cgroup_hierarchy=[^[:space:]]*)\s*/ /g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

# Add the correct parameters in the right order
# According to pelwell: DTB sets cgroup_disable=memory, cmdline.txt should only have cgroup_enable=memory
NEW_CMDLINE="$CLEAN_CMDLINE cgroup_enable=memory"

echo "🧹 Cleaned cmdline (removed conflicting cgroup params): $CLEAN_CMDLINE"
echo "✅ New cmdline (with correct override): $NEW_CMDLINE"

# Backup current file
BACKUP_FILE="${CMDLINE_FILE}.backup-$(date +%s)"
sudo cp "$CMDLINE_FILE" "$BACKUP_FILE"
echo "💾 Backed up current cmdline.txt to: $BACKUP_FILE"

# Write the corrected cmdline
echo "$NEW_CMDLINE" | sudo tee "$CMDLINE_FILE" > /dev/null
echo "✅ Updated cmdline.txt with correct parameter order"

# Show final result
echo -e "\n📝 Final cmdline.txt:"
cat "$CMDLINE_FILE"

echo -e "\n🔄 Expected behavior after reboot:"
echo "1. DTB bootargs: ... cgroup_disable=memory ..."
echo "2. cmdline.txt:   ... cgroup_enable=memory"
echo "3. Final order:   ... cgroup_disable=memory ... cgroup_enable=memory"
echo "4. Result:        cgroup_enable overrides cgroup_disable ✅"

echo -e "\n💡 Technical explanation:"
echo "- Pi 5 DTB contains cgroup_disable=memory (intentional default)"
echo "- cmdline.txt parameters are processed AFTER DTB parameters"
echo "- cgroup_enable=memory in cmdline.txt overrides the DTB setting"
echo "- Order in final /proc/cmdline matters: last parameter wins"

# Clean up any unnecessary Docker workarounds
if [ -f /etc/docker/daemon.json ]; then
    echo -e "\n🧹 Found Docker daemon.json - backing up (may not be needed after fix)"
    sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.backup-$(date +%s)"
fi

echo -e "\n⚠️  IMPORTANT: Reboot is required for changes to take effect"
read -p "🔄 Reboot now to test the fix? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Rebooting to apply parameter order fix..."
    sudo reboot
else
    echo "💡 Reboot with: sudo reboot"
    echo "🧪 After reboot, test with:"
    echo "   cat /proc/cmdline | grep cgroup"
    echo "   cat /sys/fs/cgroup/cgroup.subtree_control"
    echo "   docker run --rm hello-world"
fi