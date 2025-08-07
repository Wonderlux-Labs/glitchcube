#!/bin/bash

# Health check script for Glitch Cube on Mac Mini
# Can be run locally or remotely via SSH

# Configuration
HASS_VM_IP="${HASS_VM_IP:-192.168.1.100}"
API_PORT="${API_PORT:-4567}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}   Glitch Cube System Health Check${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Function to check service
check_service() {
    local service_name=$1
    local check_command=$2
    local status_text=$3
    
    if eval "$check_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $service_name: $status_text"
        return 0
    else
        echo -e "${RED}✗${NC} $service_name: Not running"
        return 1
    fi
}

# 1. Check Redis
check_service "Redis" "redis-cli ping" "Running ($(redis-cli info server | grep redis_version | cut -d: -f2 | tr -d '\r'))"

# 2. Check PostgreSQL
if pg_isready -q 2>/dev/null; then
    db_version=$(psql -U postgres -t -c "SELECT version();" 2>/dev/null | head -1 | awk '{print $2}')
    echo -e "${GREEN}✓${NC} PostgreSQL: Running (version $db_version)"
    
    # Check if database exists
    if psql -U postgres -lqt | cut -d \| -f 1 | grep -qw glitchcube_production; then
        echo -e "  ${GREEN}→${NC} Database 'glitchcube_production' exists"
    else
        echo -e "  ${YELLOW}⚠${NC} Database 'glitchcube_production' not found"
    fi
else
    echo -e "${RED}✗${NC} PostgreSQL: Not running"
fi

# 3. Check VMware
if pgrep -x "vmware-vmx" > /dev/null; then
    vm_count=$(pgrep -x "vmware-vmx" | wc -l | tr -d ' ')
    echo -e "${GREEN}✓${NC} VMware Fusion: Running ($vm_count VM(s) active)"
else
    echo -e "${YELLOW}⚠${NC} VMware Fusion: Not running"
fi

# 4. Check Home Assistant
echo -n "Home Assistant: "
if curl -s -o /dev/null -w "%{http_code}" "http://${HASS_VM_IP}:8123" 2>/dev/null | grep -q "200\|401"; then
    # Get HA version if possible
    ha_version=$(curl -s "http://${HASS_VM_IP}:8123/api/" 2>/dev/null | grep -o '"version":"[^"]*' | cut -d'"' -f4)
    if [ -n "$ha_version" ]; then
        echo -e "${GREEN}✓${NC} Running at ${HASS_VM_IP}:8123 (version $ha_version)"
    else
        echo -e "${GREEN}✓${NC} Running at ${HASS_VM_IP}:8123"
    fi
else
    echo -e "${RED}✗${NC} Not responding at ${HASS_VM_IP}:8123"
fi

# 5. Check Glitch Cube API
echo -n "Glitch Cube API: "
if response=$(curl -s "http://localhost:${API_PORT}/health" 2>/dev/null); then
    echo -e "${GREEN}✓${NC} Running on port ${API_PORT}"
    if [ -n "$response" ]; then
        echo -e "  ${GREEN}→${NC} Health response: $response"
    fi
else
    echo -e "${RED}✗${NC} Not responding on port ${API_PORT}"
fi

# 6. Check Sidekiq
if pgrep -f sidekiq > /dev/null; then
    sidekiq_pid=$(pgrep -f sidekiq | head -1)
    echo -e "${GREEN}✓${NC} Sidekiq: Running (PID: $sidekiq_pid)"
    
    # Check Redis queue sizes
    default_queue=$(redis-cli llen glitchcube:queue:default 2>/dev/null || echo "0")
    low_queue=$(redis-cli llen glitchcube:queue:low 2>/dev/null || echo "0")
    critical_queue=$(redis-cli llen glitchcube:queue:critical 2>/dev/null || echo "0")
    
    echo -e "  ${GREEN}→${NC} Queue sizes: critical=$critical_queue, default=$default_queue, low=$low_queue"
else
    echo -e "${RED}✗${NC} Sidekiq: Not running"
fi

# 7. Check Puma
if pgrep -f puma > /dev/null; then
    puma_pid=$(pgrep -f puma | head -1)
    echo -e "${GREEN}✓${NC} Puma: Running (PID: $puma_pid)"
else
    echo -e "${YELLOW}⚠${NC} Puma: Not detected (may be using rackup)"
fi

# 8. Check disk space
echo ""
echo -e "${BLUE}System Resources:${NC}"
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$disk_usage" -lt 80 ]; then
    echo -e "${GREEN}✓${NC} Disk usage: ${disk_usage}%"
elif [ "$disk_usage" -lt 90 ]; then
    echo -e "${YELLOW}⚠${NC} Disk usage: ${disk_usage}% (getting full)"
else
    echo -e "${RED}✗${NC} Disk usage: ${disk_usage}% (critically full)"
fi

# 9. Check memory
if command -v vm_stat > /dev/null; then
    # macOS memory check
    mem_info=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
    mem_free=$((mem_info * 4096 / 1024 / 1024))
    echo -e "${GREEN}✓${NC} Free memory: ${mem_free} MB"
fi

# 10. Check logs for recent errors
echo ""
echo -e "${BLUE}Recent Log Activity:${NC}"

LOG_DIR="/Users/eristmini/glitch/glitchcube/logs"
if [ -d "$LOG_DIR" ]; then
    # Check for recent errors in last 100 lines of logs
    error_count=$(tail -n 100 "$LOG_DIR"/*.log 2>/dev/null | grep -ci "error\|exception\|fatal" || echo "0")
    if [ "$error_count" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} No recent errors in logs"
    else
        echo -e "${YELLOW}⚠${NC} Found $error_count error(s) in recent logs"
        echo "  Check: $LOG_DIR/"
    fi
else
    echo -e "${YELLOW}⚠${NC} Log directory not found at $LOG_DIR"
fi

# 11. Check LaunchAgent status
echo ""
echo -e "${BLUE}Startup Service:${NC}"
if launchctl list | grep -q "com.glitchcube.startup"; then
    status=$(launchctl list | grep "com.glitchcube.startup" | awk '{print $2}')
    if [ "$status" = "0" ]; then
        echo -e "${GREEN}✓${NC} LaunchAgent installed and last run succeeded"
    else
        echo -e "${YELLOW}⚠${NC} LaunchAgent installed but last run had exit code: $status"
    fi
else
    echo -e "${YELLOW}⚠${NC} LaunchAgent not installed"
    echo "  Run: ./install_mac_mini_startup.sh to install"
fi

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}   Health Check Complete${NC}"
echo -e "${BLUE}=========================================${NC}"