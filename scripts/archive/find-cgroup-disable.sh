#!/bin/bash

# Find where cgroup_disable=memory is being set
# Usage: ./scripts/find-cgroup-disable.sh

echo "🔍 Hunting for cgroup_disable=memory setting..."

# Check current active kernel parameters
echo "🐧 Current kernel parameters:"
cat /proc/cmdline | tr ' ' '\n' | grep -E "(cgroup|memory)"

echo -e "\n📁 Checking boot configuration files..."

# Check cmdline.txt
echo "1. /boot/firmware/cmdline.txt:"
if [ -f /boot/firmware/cmdline.txt ]; then
    cat /boot/firmware/cmdline.txt
    if grep -q "cgroup_disable=memory" /boot/firmware/cmdline.txt; then
        echo "   ✅ Found cgroup_disable=memory here"
    else
        echo "   ❌ Not found here"
    fi
else
    echo "   ❌ File not found"
fi

# Check config.txt
echo -e "\n2. /boot/firmware/config.txt:"
if [ -f /boot/firmware/config.txt ]; then
    if grep -q "cgroup_disable" /boot/firmware/config.txt; then
        echo "   ✅ Found cgroup settings:"
        grep "cgroup" /boot/firmware/config.txt
    else
        echo "   ❌ No cgroup settings found"
    fi
else
    echo "   ❌ File not found"
fi

# Check for device-specific configs
echo -e "\n3. Checking for device-specific configs..."
for file in /boot/firmware/*.txt; do
    if [ -f "$file" ] && [ "$(basename "$file")" != "cmdline.txt" ] && [ "$(basename "$file")" != "config.txt" ]; then
        if grep -q "cgroup" "$file" 2>/dev/null; then
            echo "   ✅ Found cgroup in $file:"
            grep "cgroup" "$file"
        fi
    fi
done

# Check systemd boot entries
echo -e "\n4. Checking systemd boot entries..."
if [ -d /boot/loader/entries ]; then
    for entry in /boot/loader/entries/*.conf; do
        if [ -f "$entry" ] && grep -q "cgroup" "$entry"; then
            echo "   ✅ Found cgroup in $entry:"
            grep "cgroup" "$entry"
        fi
    done
else
    echo "   ❌ No systemd boot entries found"
fi

# Check if it's a Pi 5 specific issue
echo -e "\n5. Raspberry Pi model:"
if [ -f /proc/device-tree/model ]; then
    cat /proc/device-tree/model
    echo ""
fi

# Check for overlays that might set this
echo -e "\n6. Checking device tree overlays..."
if [ -f /boot/firmware/config.txt ]; then
    echo "Active overlays:"
    grep "^dtoverlay=" /boot/firmware/config.txt | head -10
fi

echo -e "\n🔧 Potential solutions:"
echo "1. If it's in config.txt: Remove or comment out the cgroup_disable line"
echo "2. If it's Pi 5 specific: Try adding 'cgroup_enable=memory' to cmdline.txt"
echo "3. If it's hardware default: Create Docker override config"
echo "4. Nuclear option: Reinstall Pi OS"

echo -e "\n💡 Quick test - try adding memory cgroup to cmdline.txt:"
echo "Add this to the end of /boot/firmware/cmdline.txt:"
echo "cgroup_enable=memory cgroup_memory=1"