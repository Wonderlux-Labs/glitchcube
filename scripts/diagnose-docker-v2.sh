#!/bin/bash

echo "🔍 Advanced Docker Diagnostic (cgroup v2 aware)..."
echo "=================================================="

# System info
echo "🖥️  System Information:"
echo "Kernel: $(uname -r)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
if [ -f /proc/device-tree/model ]; then
    echo "Hardware: $(cat /proc/device-tree/model)"
fi
echo ""

# Check cgroup version and controllers
echo "⚙️  CGroup Analysis:"
echo "-------------------"

# Check what cgroup version we're using
if [ -d /sys/fs/cgroup/unified ]; then
    echo "✅ cgroup v2 (unified) hierarchy detected"
elif [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    echo "✅ cgroup v2 detected at /sys/fs/cgroup"
else
    echo "⚠️  cgroup v1 or mixed mode detected"
fi

# Show available controllers
if [ -f /sys/fs/cgroup/cgroup.subtree_control ]; then
    CONTROLLERS=$(cat /sys/fs/cgroup/cgroup.subtree_control)
    echo "Available controllers: $CONTROLLERS"
    
    if echo "$CONTROLLERS" | grep -q "memory"; then
        echo "✅ Memory controller is ENABLED in cgroup v2"
    else
        echo "❌ Memory controller is DISABLED in cgroup v2"
    fi
    
    if echo "$CONTROLLERS" | grep -q "cpu"; then
        echo "✅ CPU controller is enabled"
    fi
    
    if echo "$CONTROLLERS" | grep -q "pids"; then
        echo "✅ PID controller is enabled"  
    fi
else
    echo "❌ cgroup v2 subtree_control not found"
fi

# Legacy cgroup v1 check (for reference only)
echo ""
echo "📊 Legacy cgroup v1 status (for reference):"
if [ -f /proc/cgroups ]; then
    grep memory /proc/cgroups || echo "   Memory not in /proc/cgroups (normal for newer kernels)"
else
    echo "   /proc/cgroups not available"
fi

echo ""

# Docker service status
echo "🐳 Docker Service Analysis:"
echo "---------------------------"

# Service status
if systemctl is-active --quiet docker; then
    echo "✅ Docker service is active"
    
    # Check when it started
    START_TIME=$(systemctl show docker --property=ActiveEnterTimestamp --value)
    echo "   Started: $START_TIME"
    
    # Check if it's been restarting
    RESTART_COUNT=$(systemctl show docker --property=NRestarts --value)
    echo "   Restart count: $RESTART_COUNT"
else
    echo "❌ Docker service is not active"
    systemctl status docker --no-pager -l
fi

# Check Docker daemon logs for errors
echo ""
echo "📋 Recent Docker daemon logs:"
echo "-----------------------------"
journalctl -u docker --no-pager -n 20 --since "5 minutes ago" | tail -10

echo ""

# Docker daemon responsiveness test
echo "🔗 Docker Daemon Connectivity:"
echo "------------------------------"

# Test socket connectivity
if [ -S /var/run/docker.sock ]; then
    echo "✅ Docker socket exists"
    
    # Test basic connectivity with shorter timeout
    echo "Testing daemon responsiveness..."
    if timeout 5s docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
        echo "✅ Docker daemon is responding"
        DOCKER_VERSION=$(docker version --format '{{.Server.Version}}')
        echo "   Docker version: $DOCKER_VERSION"
    else
        echo "❌ Docker daemon not responding (5s timeout)"
        
        # Check if daemon is stuck
        echo ""
        echo "🔍 Checking if daemon is stuck..."
        
        # Check Docker processes
        DOCKER_PIDS=$(pgrep -f dockerd)
        if [ -n "$DOCKER_PIDS" ]; then
            echo "Docker processes running (PIDs: $DOCKER_PIDS)"
            
            # Check if processes are consuming CPU
            for pid in $DOCKER_PIDS; do
                if [ -f /proc/$pid/stat ]; then
                    echo "   PID $pid: $(ps -p $pid -o pid,pcpu,pmem,time,cmd --no-headers)"
                fi
            done
        else
            echo "❌ No Docker processes found"
        fi
        
        # Check for common Docker issues
        echo ""
        echo "🔍 Common issue checks:"
        
        # Check disk space
        DISK_USAGE=$(df /var/lib/docker 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
        if [ -n "$DISK_USAGE" ] && [ "$DISK_USAGE" -gt 90 ]; then
            echo "⚠️  Disk space low: ${DISK_USAGE}% used"
        else
            echo "✅ Disk space OK: ${DISK_USAGE}% used" 
        fi
        
        # Check for conflicting network config
        if docker network ls >/dev/null 2>&1; then
            echo "✅ Docker network commands working"
        else
            echo "❌ Docker network commands failing"
        fi
    fi
else
    echo "❌ Docker socket not found at /var/run/docker.sock"
fi

echo ""

# Test container run if daemon is responsive
echo "🧪 Container Test:"
echo "-----------------"
if timeout 10s docker version >/dev/null 2>&1; then
    echo "Testing container creation..."
    if timeout 30s docker run --rm hello-world >/dev/null 2>&1; then
        echo "✅ Container test successful"
    else
        echo "❌ Container test failed"
        echo ""
        echo "Detailed error:"
        timeout 30s docker run --rm hello-world 2>&1 | head -10
    fi
else
    echo "⏭️  Skipping container test (daemon not responding)"
fi

echo ""

# Memory and resource checks
echo "💾 System Resources:"
echo "-------------------"
echo "Memory usage: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
echo "Load average: $(uptime | awk -F'load average:' '{print $2}')"

# Temperature (Pi specific)
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$((TEMP / 1000))
    echo "CPU temperature: ${TEMP_C}°C"
    
    if [ "$TEMP_C" -gt 80 ]; then
        echo "⚠️  High temperature detected"
    fi
fi

echo ""
echo "🔧 Recommended Actions:"
echo "----------------------"

# Provide specific recommendations
if ! timeout 5s docker version >/dev/null 2>&1; then
    echo "1. Docker daemon is not responding:"
    echo "   sudo systemctl restart docker"
    echo ""
    echo "2. If restart fails, check logs:"
    echo "   journalctl -u docker -f"
    echo ""
    echo "3. If issues persist, try emergency reset:"
    echo "   sudo systemctl stop docker"
    echo "   sudo rm -rf /var/lib/docker/tmp/*"
    echo "   sudo systemctl start docker"
fi

if [ -f /sys/fs/cgroup/cgroup.subtree_control ]; then
    if ! grep -q "memory" /sys/fs/cgroup/cgroup.subtree_control; then
        echo "4. Memory cgroup not enabled - reboot after cgroup fix"
    fi
fi

echo ""
echo "✅ Diagnostic complete"