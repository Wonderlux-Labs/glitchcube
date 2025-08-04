#!/bin/bash
# Glitch Cube Update Script
# Safely updates the art installation by building in a clean environment

set -e  # Exit on any error

# Configuration
REPO_URL="${GLITCHCUBE_REPO:-https://github.com/your-org/glitchcube.git}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES=("glitchcube" "sidekiq" "homeassistant" "mosquitto" "esphome" "music-assistant" "glances")
LOG_FILE="$APP_DIR/update.log"

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
    cleanup
    exit 1
}

cleanup() {
    if [[ -n "$BUILD_DIR" && -d "$BUILD_DIR" ]]; then
        log "${YELLOW}Cleaning up build directory: $BUILD_DIR${NC}"
        rm -rf "$BUILD_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

echo "🎲 Glitch Cube Update Script"
echo "============================="
log "${BLUE}Starting update process...${NC}"

# Verify prerequisites
if ! command -v git &> /dev/null; then
    error_exit "git is not installed or not in PATH"
fi

if ! command -v docker-compose &> /dev/null; then
    error_exit "docker-compose is not installed or not in PATH"
fi

# Check if we're in the right directory
if [[ ! -f "$APP_DIR/docker-compose.yml" ]]; then
    error_exit "docker-compose.yml not found in $APP_DIR"
fi

# Create backup of current state
log "${YELLOW}Creating backup of current state...${NC}"
BACKUP_DIR="$APP_DIR/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$APP_DIR/docker-compose.yml" "$BACKUP_DIR/"
cp "$APP_DIR/docker-compose.production.yml" "$BACKUP_DIR/" 2>/dev/null || true
cp "$APP_DIR/.env" "$BACKUP_DIR/" 2>/dev/null || true
log "${GREEN}Backup created at: $BACKUP_DIR${NC}"

# Create temporary build directory
BUILD_DIR=$(mktemp -d -t glitchcube-build-XXXXXX)
log "${BLUE}Created build directory: $BUILD_DIR${NC}"

# Clone/pull latest code
if [[ -n "${GLITCHCUBE_BRANCH:-}" ]]; then
    log "${BLUE}Cloning branch: $GLITCHCUBE_BRANCH${NC}"
    git clone -b "$GLITCHCUBE_BRANCH" "$REPO_URL" "$BUILD_DIR" || error_exit "Git clone failed"
else
    log "${BLUE}Cloning latest main branch...${NC}"
    git clone "$REPO_URL" "$BUILD_DIR" || error_exit "Git clone failed"
fi

# Show what we're updating to
cd "$BUILD_DIR"
COMMIT_HASH=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=format:"%s")
log "${BLUE}Building commit: $COMMIT_HASH - $COMMIT_MSG${NC}"

# Copy production overrides if they exist
if [[ -f "$APP_DIR/.env" ]]; then
    log "${YELLOW}Copying production .env file...${NC}"
    cp "$APP_DIR/.env" "$BUILD_DIR/"
fi

# Build Docker images
log "${BLUE}Building Docker images...${NC}"
docker-compose build --parallel || error_exit "Docker build failed"

# Tag images with timestamp for rollback capability
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
for service in "${SERVICES[@]}"; do
    if docker images | grep -q "glitchcube.*$service"; then
        docker tag "glitchcube_$service:latest" "glitchcube_$service:$TIMESTAMP" 2>/dev/null || true
    fi
done

log "${GREEN}Images built successfully${NC}"

# Return to app directory for deployment
cd "$APP_DIR"

# Check current service status
log "${BLUE}Checking current service status...${NC}"
docker-compose -f docker-compose.yml -f docker-compose.production.yml ps

# Restart services with minimal downtime
log "${BLUE}Updating services...${NC}"

# Update services that don't require data persistence first
for service in mosquitto glances; do
    if docker-compose -f docker-compose.yml -f docker-compose.production.yml ps | grep -q "$service"; then
        log "${YELLOW}Updating $service...${NC}"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml stop "$service"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml rm -f "$service"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d "$service"
    fi
done

# Update application services (preserve data volumes)
for service in glitchcube sidekiq; do
    if docker-compose -f docker-compose.yml -f docker-compose.production.yml ps | grep -q "$service"; then
        log "${YELLOW}Updating $service...${NC}"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml stop "$service"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml rm -f "$service"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d "$service"
    fi
done

# Update other services
for service in esphome music-assistant; do
    if docker-compose -f docker-compose.yml -f docker-compose.production.yml ps | grep -q "$service"; then
        log "${YELLOW}Updating $service...${NC}"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml stop "$service"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml rm -f "$service"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d "$service"
    fi
done

# Home Assistant last (most critical, longest startup time)
if docker-compose -f docker-compose.yml -f docker-compose.production.yml ps | grep -q homeassistant; then
    log "${YELLOW}Updating Home Assistant (this may take a moment)...${NC}"
    docker-compose -f docker-compose.yml -f docker-compose.production.yml stop homeassistant
    docker-compose -f docker-compose.yml -f docker-compose.production.yml rm -f homeassistant
    docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d homeassistant
fi

# Wait for services to be healthy
log "${BLUE}Waiting for services to be healthy...${NC}"
sleep 10

# Check final status
log "${BLUE}Final service status:${NC}"
docker-compose -f docker-compose.yml -f docker-compose.production.yml ps

# Health check
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

if [[ $HEALTH_CHECK_FAILED -eq 1 ]]; then
    log "${YELLOW}⚠️  Some health checks failed, but update completed. Check logs for details.${NC}"
    log "${YELLOW}Rollback command: docker-compose -f docker-compose.yml -f docker-compose.production.yml down && [restore from $BACKUP_DIR]${NC}"
else
    log "${GREEN}🎉 All services updated successfully!${NC}"
fi

# Show service URLs
echo ""
echo "🌐 Service URLs:"
echo "   Glitch Cube API: http://$(hostname -I | cut -d' ' -f1):4567"
echo "   Home Assistant: http://$(hostname -I | cut -d' ' -f1):8123"
echo "   ESPHome: http://$(hostname -I | cut -d' ' -f1):6052"
echo "   Music Assistant: http://$(hostname -I | cut -d' ' -f1):8095"
echo "   System Monitor: http://$(hostname -I | cut -d' ' -f1):61208"
echo "   Portainer: https://$(hostname -I | cut -d' ' -f1):9443"
echo ""

log "${GREEN}Update completed! Build artifacts cleaned up.${NC}"
echo "📋 Update log: $LOG_FILE"