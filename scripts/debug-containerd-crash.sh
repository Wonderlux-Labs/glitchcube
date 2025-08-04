#!/bin/bash

echo "🔍 Debugging containerd crash with core dump analysis..."
echo "======================================================"

echo "🔧 Step 1: Enable core dumps for containerd..."

# Create backup of containerd service file
sudo cp /lib/systemd/system/containerd.service /lib/systemd/system/containerd.service.backup-$(date +%s)

# Check current LimitCORE setting
echo "Current containerd service configuration:"
grep -n "LimitCORE" /lib/systemd/system/containerd.service || echo "No LimitCORE setting found"

# Create systemd drop-in directory for containerd overrides
sudo mkdir -p /etc/systemd/system/containerd.service.d

# Create drop-in file to enable core dumps
cat << 'EOF' | sudo tee /etc/systemd/system/containerd.service.d/enable-coredumps.conf
[Service]
LimitCORE=infinity
WorkingDirectory=/tmp
EOF

echo "✅ Created core dump override: /etc/systemd/system/containerd.service.d/enable-coredumps.conf"

# Set global core dump settings
echo "🔧 Step 2: Configure system core dump settings..."

# Ensure core dumps are enabled system-wide
echo "* soft core unlimited" | sudo tee -a /etc/security/limits.conf
echo "* hard core unlimited" | sudo tee -a /etc/security/limits.conf

# Set core dump pattern to include PID and timestamp
echo "/tmp/core.%e.%p.%t" | sudo tee /proc/sys/kernel/core_pattern

# Make core dump pattern persistent
echo "kernel.core_pattern = /tmp/core.%e.%p.%t" | sudo tee -a /etc/sysctl.conf

echo "✅ Core dumps will be saved as: /tmp/core.<process>.<pid>.<timestamp>"

echo ""
echo "🔧 Step 3: Reload systemd and prepare for crash analysis..."

sudo systemctl daemon-reload

# Stop containerd if running
sudo systemctl stop containerd || true

# Clear old core dumps
sudo rm -f /tmp/core.containerd.* || true

echo ""
echo "🔧 Step 4: Collect system information before crash test..."
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -r)"
echo "CPU info:"
cat /proc/cpuinfo | grep -E "(processor|model name|Features|CPU)" | head -10

echo ""
echo "Containerd binary info:"
if [ -f /usr/bin/containerd ]; then
    file /usr/bin/containerd
    ls -la /usr/bin/containerd
    
    # Check for required libraries
    echo ""
    echo "Library dependencies:"
    ldd /usr/bin/containerd | head -10
else
    echo "❌ containerd binary not found"
fi

echo ""
echo "🚨 Step 5: Attempt to start containerd and capture crash..."

# Start containerd in foreground to capture immediate crash
echo "Starting containerd with core dumps enabled..."
echo "This will likely crash - that's expected, we want to capture the core dump"

# Set ulimits for this session
ulimit -c unlimited

# Try to start containerd
sudo systemctl start containerd &
CONTAINERD_PID=$!

# Wait a few seconds for crash
sleep 5

# Check if containerd is still trying to restart
echo ""
echo "📊 Containerd service status after crash attempt:"
sudo systemctl status containerd --no-pager -l

echo ""
echo "🔍 Step 6: Analyze crash artifacts..."

# Look for core dumps
echo "Looking for core dumps in /tmp/..."
CORE_FILES=$(ls /tmp/core.containerd.* 2>/dev/null || echo "")

if [ -n "$CORE_FILES" ]; then
    echo "✅ Found core dump files:"
    ls -la /tmp/core.containerd.*
    
    echo ""
    echo "🔬 Analyzing core dump with gdb (if available)..."
    if command -v gdb &> /dev/null; then
        # Install gdb if needed
        echo "GDB is available"
        
        for core_file in /tmp/core.containerd.*; do
            echo ""
            echo "=== Analyzing $core_file ==="
            echo "bt" | sudo gdb -batch -ex "set confirm off" /usr/bin/containerd "$core_file" 2>/dev/null || echo "GDB analysis failed"
        done
    else
        echo "Installing gdb for crash analysis..."
        sudo apt-get update && sudo apt-get install -y gdb
        
        if command -v gdb &> /dev/null; then
            for core_file in /tmp/core.containerd.*; do
                echo ""
                echo "=== Analyzing $core_file ==="
                echo -e "bt\nquit" | sudo gdb /usr/bin/containerd "$core_file" 2>/dev/null || echo "GDB analysis failed"
            done
        else
            echo "⚠️  Could not install gdb for analysis"
        fi
    fi
else
    echo "❌ No core dump files found"
    
    # Check if core dumps are being generated elsewhere
    echo ""
    echo "Checking for core dumps in other locations..."
    sudo find /var/crash /var/lib/systemd/coredump /tmp -name "*core*" -o -name "*containerd*" 2>/dev/null || echo "No core dumps found"
    
    # Check systemd coredump service
    if command -v coredumpctl &> /dev/null; then
        echo ""
        echo "Checking systemd coredumpctl..."
        sudo coredumpctl list containerd 2>/dev/null || echo "No containerd crashes in coredumpctl"
    fi
fi

echo ""
echo "🔍 Step 7: Alternative crash analysis..."

# Try running containerd directly to see immediate error
echo "Attempting to run containerd directly for immediate error output..."
timeout 5s sudo /usr/bin/containerd --help >/dev/null 2>&1 && echo "✅ containerd --help works" || echo "❌ containerd --help failed"
timeout 2s sudo /usr/bin/containerd --version 2>&1 || echo "❌ containerd --version failed"

echo ""
echo "📋 Step 8: System diagnostics..."

# Check for missing dependencies
echo "Checking for missing shared libraries..."
ldd /usr/bin/containerd | grep "not found" || echo "✅ All shared libraries found"

# Check for CPU feature compatibility
echo ""
echo "CPU features:"
cat /proc/cpuinfo | grep Features | head -1

# Check for kernel modules
echo ""
echo "Relevant kernel modules:"
lsmod | grep -E "(overlay|br_netfilter|iptable)" || echo "No relevant modules loaded"

echo ""
echo "💡 Next steps based on findings:"
echo "1. If core dump found: Analyze with gdb for exact crash location"
echo "2. If library missing: Install missing dependencies"
echo "3. If CPU incompatible: Try alternative containerd build"
echo "4. If all else fails: Use Docker without containerd (podman alternative)"

echo ""
echo "🔧 To disable core dumps and restore normal operation:"
echo "sudo rm /etc/systemd/system/containerd.service.d/enable-coredumps.conf"
echo "sudo systemctl daemon-reload"