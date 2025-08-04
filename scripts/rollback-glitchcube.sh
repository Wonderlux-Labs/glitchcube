#!/bin/bash
# Glitch Cube Rollback Script
# Rolls back to previous Docker images using tagged timestamps

set -e

# Configuration
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES=("homeassistant" "glitchcube" "sidekiq" "mosquitto" "esphome" "music-assistant" "glances")
LOG_FILE="$APP_DIR/rollback.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Check arguments
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <timestamp>"
    echo ""
    echo "Available rollback timestamps:"
    if [[ -f "$APP_DIR/last-rollback-tag.txt" ]]; then
        echo "  Latest: $(cat "$APP_DIR/last-rollback-tag.txt")"
    fi
    
    # Show available tagged images
    echo ""
    echo "Docker image tags:"
    docker images | grep glitchcube | grep -E "_[0-9]{8}_[0-9]{6}" | awk '{print $2}' | sort -u
    exit 1
fi

ROLLBACK_TIMESTAMP="$1"

echo "🔄 Glitch Cube Rollback Script"
echo "=============================="
log "${BLUE}Starting rollback to timestamp: $ROLLBACK_TIMESTAMP${NC}"

# Verify timestamp format
if [[ ! "$ROLLBACK_TIMESTAMP" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
    error_exit "Invalid timestamp format. Expected: YYYYMMDD_HHMMSS (e.g., 20240101_120000)"
fi

# Check if rollback images exist
IMAGES_EXIST=0
for service in "${SERVICES[@]}"; do
    if docker images | grep -q "glitchcube_$service.*$ROLLBACK_TIMESTAMP"; then
        IMAGES_EXIST=1
        log "${GREEN}Found rollback image: glitchcube_$service:$ROLLBACK_TIMESTAMP${NC}"
    fi
done

if [[ $IMAGES_EXIST -eq 0 ]]; then
    error_exit "No rollback images found for timestamp $ROLLBACK_TIMESTAMP"
fi

# Check if we're in the right directory
if [[ ! -f "$APP_DIR/docker-compose.yml" ]]; then
    error_exit "docker-compose.yml not found in $APP_DIR"
fi

# Create rollback backup of current state
log "${YELLOW}Creating backup of current state before rollback...${NC}"
BACKUP_DIR="$APP_DIR/backups/rollback_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$APP_DIR/docker-compose.yml" "$BACKUP_DIR/"
cp "$APP_DIR/docker-compose.production.yml" "$BACKUP_DIR/" 2>/dev/null || true
cp "$APP_DIR/.env" "$BACKUP_DIR/" 2>/dev/null || true
log "${GREEN}Backup created at: $BACKUP_DIR${NC}"

# Function to rollback a service
rollback_service() {
    local service="$1"
    local description="${2:-$service}"
    
    # Check if rollback image exists for this service
    if ! docker images | grep -q "glitchcube_$service.*$ROLLBACK_TIMESTAMP"; then
        log "${YELLOW}No rollback image for $service, skipping...${NC}"
        return 0
    fi
    
    log "${YELLOW}Rolling back $description...${NC}"
    
    # Stop current service
    docker-compose -f docker-compose.yml -f docker-compose.production.yml stop "$service" 2>/dev/null || true
    docker-compose -f docker-compose.yml -f docker-compose.production.yml rm -f "$service" 2>/dev/null || true
    
    # Tag rollback image as latest
    docker tag "glitchcube_$service:$ROLLBACK_TIMESTAMP" "glitchcube_$service:latest"
    
    # Start service with rolled back image
    docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d "$service"
    
    # Brief pause
    sleep 2
    
    log "${GREEN}✅ $description rolled back successfully${NC}"
}

# Rollback services in reverse dependency order
log "${BLUE}Rolling back services...${NC}"

# Stop integration services first
rollback_service "music-assistant" "Music Assistant"
rollback_service "esphome" "ESPHome Dashboard"

# Core application services
rollback_service "sidekiq" "Background Jobs"
rollback_service "glitchcube" "Glitch Cube Application"

# Infrastructure services
rollback_service "glances" "System Monitor"
rollback_service "mosquitto" "MQTT Broker"

# Home Assistant last (foundation service)
rollback_service "homeassistant" "Home Assistant"

# Wait for services to stabilize
log "${BLUE}Waiting for services to stabilize...${NC}"
sleep 15

# Health checks
log "${BLUE}Running health checks...${NC}"
HEALTH_CHECK_FAILED=0

# Check Glitch Cube API
if curl -f -s "http://localhost:4567/health" > /dev/null; then
    log "${GREEN}✅ Glitch Cube API is healthy${NC}"
else
    log "${RED}❌ Glitch Cube API health check failed${NC}"
    HEALTH_CHECK_FAILED=1
fi

# Check Home Assistant
if curl -f -s "http://localhost:8123/api/" > /dev/null; then
    log "${GREEN}✅ Home Assistant is healthy${NC}"
else
    log "${RED}❌ Home Assistant health check failed${NC}"
    HEALTH_CHECK_FAILED=1
fi

# Final status
echo ""
if [[ $HEALTH_CHECK_FAILED -eq 1 ]]; then
    log "${YELLOW}⚠️  Some health checks failed after rollback. Check logs for details.${NC}"
    echo "🔧 Troubleshooting:"
    echo "   - Check service logs: docker-compose logs -f"
    echo "   - Manual restore from: $BACKUP_DIR"
else
    log "${GREEN}🎉 Rollback completed successfully!${NC}"
fi

# Show final status
echo ""
echo "📊 Final service status:"
docker-compose -f docker-compose.yml -f docker-compose.production.yml ps

echo ""
echo "🌐 Service URLs:"
echo "   Glitch Cube API: http://$(hostname -I | cut -d' ' -f1):4567"
echo "   Home Assistant: http://$(hostname -I | cut -d' ' -f1):8123"
echo "   ESPHome: http://$(hostname -I | cut -d' ' -f1):6052"
echo "   Music Assistant: http://$(hostname -I | cut -d' ' -f1):8095"
echo "   System Monitor: http://$(hostname -I | cut -d' ' -f1):61208"

echo ""
log "${GREEN}Rollback completed! Rollback log: $LOG_FILE${NC}"