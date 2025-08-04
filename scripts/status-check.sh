#!/bin/bash
# Glitch Cube Status Check Script
# Gallery staff-friendly system status checker

set -e

# Configuration
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES=("homeassistant" "glitchcube" "sidekiq" "mosquitto" "esphome" "music-assistant" "glances")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Icons
CHECKMARK="✅"
CROSSMARK="❌"
WARNING="⚠️"
INFO="ℹ️"

# Header
echo -e "${BOLD}🎲 Glitch Cube System Status${NC}"
echo "================================"
echo ""

# Get system info
HOSTNAME=$(hostname -I | cut -d' ' -f1 2>/dev/null || echo "localhost")
UPTIME=$(uptime | sed 's/.*up \([^,]*\).*/\1/')
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')

echo -e "${BLUE}System Information:${NC}"
echo "  IP Address: $HOSTNAME"
echo "  Uptime: $UPTIME"
echo "  Load Average: $LOAD"
echo ""

# Docker daemon check
echo -e "${BLUE}Docker Status:${NC}"
if docker info >/dev/null 2>&1; then
    echo -e "  ${CHECKMARK} Docker daemon running"
    
    # Docker resources
    DOCKER_INFO=$(docker system df --format "table {{.Type}}\t{{.Size}}\t{{.Reclaimable}}" 2>/dev/null || echo "")
    if [[ -n "$DOCKER_INFO" ]]; then
        echo "  Docker disk usage:"
        echo "$DOCKER_INFO" | sed 's/^/    /'
    fi
else
    echo -e "  ${CROSSMARK} Docker daemon not running"
    echo ""
    echo -e "${RED}${BOLD}CRITICAL: Docker is not running!${NC}"
    echo "Gallery staff should contact technical support immediately."
    exit 1
fi
echo ""

# Service status check
echo -e "${BLUE}Service Status:${NC}"
ALL_HEALTHY=true
COMPOSE_CMD="docker-compose -f docker-compose.yml -f docker-compose.production.yml"

for service in "${SERVICES[@]}"; do
    # Check if service is running
    if $COMPOSE_CMD ps | grep -q "$service.*Up"; then
        # Service is up, check if it's healthy
        HEALTH_STATUS=$($COMPOSE_CMD ps | grep "$service" | awk '{print $4}')
        
        if [[ "$HEALTH_STATUS" == *"(healthy)"* ]]; then
            echo -e "  ${CHECKMARK} $service - Running & Healthy"
        elif [[ "$HEALTH_STATUS" == *"(unhealthy)"* ]]; then
            echo -e "  ${WARNING} $service - Running but Unhealthy"
            ALL_HEALTHY=false
        else
            echo -e "  ${WARNING} $service - Running (no health check)"
        fi
    else
        echo -e "  ${CROSSMARK} $service - Not running"
        ALL_HEALTHY=false
    fi
done
echo ""

# Resource usage
echo -e "${BLUE}Resource Usage:${NC}"
if command -v free >/dev/null 2>&1; then
    MEMORY_USAGE=$(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}')
    echo "  Memory: $MEMORY_USAGE used"
fi

if command -v df >/dev/null 2>&1; then
    DISK_USAGE=$(df "$APP_DIR" | awk 'NR==2{printf "%s used (%s available)", $3, $4}')
    echo "  Disk: $DISK_USAGE"
fi
echo ""

# Health check endpoints
echo -e "${BLUE}Service Health Checks:${NC}"
HEALTH_FAILURES=0

# Glitch Cube API
if curl -f -s "http://localhost:4567/health" >/dev/null 2>&1; then
    echo -e "  ${CHECKMARK} Glitch Cube API (port 4567)"
else
    echo -e "  ${CROSSMARK} Glitch Cube API (port 4567)"
    HEALTH_FAILURES=$((HEALTH_FAILURES + 1))
    ALL_HEALTHY=false
fi

# Home Assistant
# Try to load Home Assistant token from environment or .env file
if [[ -f "$APP_DIR/.env" ]] && grep -q "HOME_ASSISTANT_TOKEN" "$APP_DIR/.env"; then
    HA_TOKEN=$(grep "HOME_ASSISTANT_TOKEN" "$APP_DIR/.env" | cut -d'=' -f2)
    if curl -f -s -H "Authorization: Bearer $HA_TOKEN" "http://localhost:8123/api/" >/dev/null 2>&1; then
        echo -e "  ${CHECKMARK} Home Assistant (port 8123)"
    else
        echo -e "  ${CROSSMARK} Home Assistant (port 8123) - API call failed"
        HEALTH_FAILURES=$((HEALTH_FAILURES + 1))
        ALL_HEALTHY=false
    fi
elif curl -f -s "http://localhost:8123/api/" >/dev/null 2>&1; then
    echo -e "  ${CHECKMARK} Home Assistant (port 8123)"
else
    echo -e "  ${CROSSMARK} Home Assistant (port 8123) - No auth token found"
    HEALTH_FAILURES=$((HEALTH_FAILURES + 1))
    ALL_HEALTHY=false
fi

# Other services (basic port checks)
check_port() {
    local port=$1
    local service=$2
    
    if nc -z localhost "$port" 2>/dev/null; then
        echo -e "  ${CHECKMARK} $service (port $port)"
    else
        echo -e "  ${CROSSMARK} $service (port $port)"
        HEALTH_FAILURES=$((HEALTH_FAILURES + 1))
        ALL_HEALTHY=false
    fi
}

check_port 6052 "ESPHome Dashboard"
check_port 8095 "Music Assistant"
check_port 61208 "System Monitor"
check_port 1883 "MQTT Broker"

echo ""

# Recent logs check
echo -e "${BLUE}Recent Issues:${NC}"
ERROR_COUNT=0

# Check for recent errors in logs
if command -v journalctl >/dev/null 2>&1; then
    RECENT_ERRORS=$(journalctl -u docker.service --since "1 hour ago" | grep -i error | wc -l)
    if [[ $RECENT_ERRORS -gt 0 ]]; then
        echo -e "  ${WARNING} $RECENT_ERRORS Docker errors in the last hour"
        ERROR_COUNT=$((ERROR_COUNT + RECENT_ERRORS))
    fi
fi

# Check Docker container logs for errors
CONTAINER_ERRORS=$($COMPOSE_CMD logs --since=1h 2>/dev/null | grep -i error | wc -l)
if [[ $CONTAINER_ERRORS -gt 0 ]]; then
    echo -e "  ${WARNING} $CONTAINER_ERRORS container errors in the last hour"
    ERROR_COUNT=$((ERROR_COUNT + CONTAINER_ERRORS))
fi

if [[ $ERROR_COUNT -eq 0 ]]; then
    echo -e "  ${CHECKMARK} No recent errors detected"
fi
echo ""

# Overall status
echo -e "${BOLD}Overall Status:${NC}"
if [[ "$ALL_HEALTHY" == true ]]; then
    echo -e "${GREEN}${BOLD}${CHECKMARK} ALL SYSTEMS OPERATIONAL${NC}"
    echo ""
    echo "🎨 The Glitch Cube installation is running normally."
    echo "All services are healthy and responding."
else
    echo -e "${RED}${BOLD}${WARNING} ISSUES DETECTED${NC}"
    echo ""
    echo "🚨 The Glitch Cube installation has issues that need attention."
    
    if [[ $HEALTH_FAILURES -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Quick troubleshooting steps:${NC}"
        echo "1. Try restarting services: ./scripts/restart-services.sh"
        echo "2. Check detailed logs: docker-compose logs -f"
        echo "3. If issues persist, contact technical support"
    fi
fi

echo ""
echo -e "${BLUE}Service URLs (if healthy):${NC}"
echo "  🎲 Glitch Cube: http://$HOSTNAME:4567"
echo "  🏠 Home Assistant: http://$HOSTNAME:8123"
echo "  🔧 ESPHome: http://$HOSTNAME:6052"
echo "  🎵 Music Assistant: http://$HOSTNAME:8095"
echo "  📊 System Monitor: http://$HOSTNAME:61208"

echo ""
echo "📋 For detailed diagnostics: docker-compose logs -f"
echo "🔄 To restart services: docker-compose restart"
echo "📞 Technical support: contact your installation team"

# Exit with appropriate code
if [[ "$ALL_HEALTHY" == true ]]; then
    exit 0
else
    exit 1
fi