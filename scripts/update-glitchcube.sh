#!/bin/bash
# Glitch Cube Update Script
# Safely updates the art installation by building in a clean environment

set -e  # Exit on any error

# Configuration
REPO_URL="${GLITCHCUBE_REPO:-https://github.com/Wonderlux-Labs/glitchcube.git}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES=("homeassistant" "glitchcube" "sidekiq" "mosquitto" "esphome" "music-assistant" "glances")
LOG_FILE="$APP_DIR/update.log"
MIN_DISK_SPACE_GB=2  # Minimum disk space required in GB
GIT_CLONE_TIMEOUT=300  # Git clone timeout in seconds

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

check_disk_space() {
    local available_gb=$(df "$APP_DIR" | awk 'NR==2 {printf "%.1f", $4/1024/1024}')
    local available_int=$(echo "$available_gb" | cut -d. -f1)
    
    if [[ $available_int -lt $MIN_DISK_SPACE_GB ]]; then
        error_exit "Insufficient disk space. Available: ${available_gb}GB, Required: ${MIN_DISK_SPACE_GB}GB"
    fi
    
    log "${GREEN}Disk space check passed: ${available_gb}GB available${NC}"
}

check_docker_daemon() {
    if ! docker info >/dev/null 2>&1; then
        error_exit "Docker daemon is not running or not accessible"
    fi
    
    # Check if we can run containers
    if ! docker run --rm hello-world >/dev/null 2>&1; then
        error_exit "Docker daemon is running but cannot execute containers"
    fi
    
    log "${GREEN}Docker daemon is healthy${NC}"
}

git_clone_with_timeout() {
    local repo_url="$1"
    local target_dir="$2"
    local branch="${3:-}"
    
    # Check if GitHub token is available and modify URL for private repos
    if [[ -n "${GITHUB_TOKEN:-}" && "$repo_url" == *"github.com"* ]]; then
        # Convert GitHub URL to use token authentication
        if [[ "$repo_url" == "https://github.com/"* ]]; then
            repo_url="${repo_url/https:\/\/github.com\//https://${GITHUB_TOKEN}@github.com/}"
            log "${BLUE}Using GitHub token for authentication${NC}"
        fi
    fi
    
    local git_cmd="git clone"
    if [[ -n "$branch" ]]; then
        git_cmd="$git_cmd -b $branch"
    fi
    git_cmd="$git_cmd $repo_url $target_dir"
    
    log "${BLUE}Running: timeout ${GIT_CLONE_TIMEOUT}s git clone [repository]${NC}"
    
    if ! timeout "$GIT_CLONE_TIMEOUT" $git_cmd; then
        if [[ $? -eq 124 ]]; then
            error_exit "Git clone timed out after ${GIT_CLONE_TIMEOUT} seconds"
        else
            error_exit "Git clone failed"
        fi
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

echo "🎲 Glitch Cube Update Script"
echo "============================="
log "${BLUE}Starting update process...${NC}"

# Load environment variables (including GitHub token)
if [[ -f "$APP_DIR/.env" ]]; then
    log "${BLUE}Loading environment variables...${NC}"
    set -a  # automatically export all variables
    source "$APP_DIR/.env.defaults" 2>/dev/null || true
    source "$APP_DIR/.env" 2>/dev/null || true
    set +a  # stop auto-exporting
fi

# Verify prerequisites
log "${BLUE}Checking prerequisites...${NC}"

if ! command -v git &> /dev/null; then
    error_exit "git is not installed or not in PATH"
fi

if ! command -v docker-compose &> /dev/null; then
    error_exit "docker-compose is not installed or not in PATH"
fi

if ! command -v timeout &> /dev/null; then
    error_exit "timeout command is not available (required for git clone timeout)"
fi

# Check if we're in the right directory
if [[ ! -f "$APP_DIR/docker-compose.yml" ]]; then
    error_exit "docker-compose.yml not found in $APP_DIR"
fi

# Check system resources
check_disk_space
check_docker_daemon

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
    git_clone_with_timeout "$REPO_URL" "$BUILD_DIR" "$GLITCHCUBE_BRANCH"
else
    log "${BLUE}Cloning latest main branch...${NC}"
    git_clone_with_timeout "$REPO_URL" "$BUILD_DIR"
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
log "${BLUE}Creating rollback tags with timestamp: $TIMESTAMP${NC}"
for service in "${SERVICES[@]}"; do
    if docker images | grep -q "glitchcube.*$service"; then
        docker tag "glitchcube_$service:latest" "glitchcube_$service:$TIMESTAMP" 2>/dev/null || true
        log "${GREEN}Tagged glitchcube_$service:$TIMESTAMP for rollback${NC}"
    fi
done

# Store rollback info
echo "$TIMESTAMP" > "$APP_DIR/last-rollback-tag.txt"

log "${GREEN}Images built successfully${NC}"

# Return to app directory for deployment
cd "$APP_DIR"

# Check current service status
log "${BLUE}Checking current service status...${NC}"
docker-compose -f docker-compose.yml -f docker-compose.production.yml ps

# Restart services with minimal downtime
log "${BLUE}Updating services in optimized order...${NC}"

# Function to update a single service
update_service() {
    local service="$1"
    local description="${2:-$service}"
    
    if docker-compose -f docker-compose.yml -f docker-compose.production.yml ps | grep -q "$service"; then
        log "${YELLOW}Updating $description...${NC}"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml stop "$service"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml rm -f "$service"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d "$service"
        
        # Brief pause to let service initialize
        sleep 2
    else
        log "${BLUE}Service $service not running, starting fresh...${NC}"
        docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d "$service"
    fi
}

# 1. Home Assistant first (foundation service, others depend on it)
update_service "homeassistant" "Home Assistant (this may take a moment)"

# 2. Infrastructure services (MQTT, monitoring)  
update_service "mosquitto" "MQTT Broker"
update_service "glances" "System Monitor"

# 3. Core application services (preserve data)
update_service "glitchcube" "Glitch Cube Application"
update_service "sidekiq" "Background Jobs"

# 4. Integration services
update_service "esphome" "ESPHome Dashboard"
update_service "music-assistant" "Music Assistant"

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
if [[ -f ".env" ]] && grep -q "HOME_ASSISTANT_TOKEN" ".env"; then
    HA_TOKEN=$(grep "HOME_ASSISTANT_TOKEN" ".env" | cut -d'=' -f2)
    if curl -f -s -H "Authorization: Bearer $HA_TOKEN" "http://localhost:8123/api/" > /dev/null 2>&1; then
        log "${GREEN}✅ Home Assistant is healthy${NC}"
    else
        log "${RED}❌ Home Assistant health check failed (with auth)${NC}"
        HEALTH_CHECK_FAILED=1
    fi
elif curl -f -s "http://localhost:8123/api/" > /dev/null 2>&1; then
    log "${GREEN}✅ Home Assistant is healthy${NC}"
else
    log "${RED}❌ Home Assistant health check failed (no auth token found)${NC}"
    HEALTH_CHECK_FAILED=1
fi

if [[ $HEALTH_CHECK_FAILED -eq 1 ]]; then
    log "${YELLOW}⚠️  Some health checks failed, but update completed. Check logs for details.${NC}"
    echo ""
    echo "🔄 To rollback this update:"
    echo "   1. Run: ./scripts/rollback-glitchcube.sh $TIMESTAMP"
    echo "   2. Or manually: Restore from backup: $BACKUP_DIR"
else
    log "${GREEN}🎉 All services updated successfully!${NC}"
    echo ""
    echo "✅ Update completed successfully!"
    echo "🔄 If you need to rollback: ./scripts/rollback-glitchcube.sh $TIMESTAMP"
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