#!/bin/bash

# Glitch Cube Mac Mini Startup Script
# This script ensures all required services are running on boot/reboot
# Install as LaunchDaemon or LaunchAgent for automatic startup

set -e

# LESSON LEARNED: Use absolute paths - LaunchAgent processes don't inherit shell configs
# Define absolute paths for all tools
BREW="/opt/homebrew/bin/brew"
REDIS_CLI="/opt/homebrew/bin/redis-cli"
PG_ISREADY="/opt/homebrew/bin/pg_isready"
CURL="/usr/bin/curl"

# Configuration
GLITCHCUBE_DIR="/Users/eristmini/glitch/glitchcube"

# Set up Ruby environment early
cd "$GLITCHCUBE_DIR"
export ASDF_DATA_DIR="$HOME/.asdf"
ASDF="/opt/homebrew/bin/asdf"
"$ASDF" set ruby 3.4.1
"$ASDF" reshim ruby
LOG_FILE="/Users/eristmini/glitch/startup.log"
INITIAL_WAIT=60  # Wait 60 seconds before first attempt
MAX_RETRIES=30  # 30 attempts after initial wait
RETRY_DELAY=10  # 10 seconds between attempts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${YELLOW}➜${NC} $1" | tee -a "$LOG_FILE"
}

# Start logging
log "========================================="
log "Starting Glitch Cube Services"
log "========================================="

# 1. Check and start Redis
log_info "Checking Redis..."
if ! pgrep -x "redis-server" > /dev/null; then
    log "Redis not running. Starting Redis..."
    "$BREW" services start redis
    sleep 3
    
    # Verify Redis started
    if "$REDIS_CLI" ping > /dev/null 2>&1; then
        log_success "Redis started successfully"
    else
        log_error "Failed to start Redis"
        exit 1
    fi
else
    log_success "Redis already running"
fi

# 2. Check and start PostgreSQL
log_info "Checking PostgreSQL..."
if ! "$PG_ISREADY" -q 2>/dev/null; then
    log "PostgreSQL not running. Starting PostgreSQL..."
    "$BREW" services start postgresql@14  # Adjust version if needed
    sleep 5
    
    # Wait for PostgreSQL to be ready
    for i in {1..10}; do
        if "$PG_ISREADY" -q 2>/dev/null; then
            log_success "PostgreSQL started successfully"
            break
        fi
        if [ $i -eq 10 ]; then
            log_error "Failed to start PostgreSQL"
            exit 1
        fi
        sleep 2
    done
else
    log_success "PostgreSQL already running"
fi

# 3. Start VMware Fusion (if not running)
log_info "Starting VMware Fusion..."
if ! pgrep -x "vmware-vmx" > /dev/null; then
    log "VMware not running, starting VMware Fusion..."
    open -a "VMware Fusion"
    sleep 15
    log_success "VMware Fusion started (VMs should auto-start)"
else
    log_success "VMware already running"
fi

# 5. Wait for Home Assistant to be accessible
log_info "Checking if Home Assistant is responding..."
HASS_UP=false

# First check if HA is already up
if "$CURL" -s -o /dev/null -w "%{http_code}" "http://glitch.local:8123" | grep -q "200\|401"; then
    HASS_UP=true
    log_success "Home Assistant is already responding at glitch.local:8123"
else
    log_info "Home Assistant not ready, waiting $INITIAL_WAIT seconds..."
    sleep $INITIAL_WAIT
    
    for i in $(seq 1 $MAX_RETRIES); do
        if "$CURL" -s -o /dev/null -w "%{http_code}" "http://glitch.local:8123" | grep -q "200\|401"; then
            HASS_UP=true
            log_success "Home Assistant is responding at glitch.local:8123"
            break
        fi
        
        log "Attempt $i/$MAX_RETRIES: Home Assistant not ready yet..."
        sleep $RETRY_DELAY
    done
fi

if [ "$HASS_UP" = false ]; then
    log_error "Home Assistant failed to respond after $MAX_RETRIES attempts"
    log "Continuing anyway..."
fi

# 6. Start Glitch Cube application
log_info "Starting Glitch Cube application..."
cd "$GLITCHCUBE_DIR"

# Pull latest code (optional)
# log "Pulling latest code from git..."
# git pull origin main

# Ensure dependencies are installed
if [ -f "Gemfile" ]; then
    log "Checking Ruby dependencies..."
    "$ASDF" exec bundle check || "$ASDF" exec bundle install
fi

# Kill any existing Ruby/Sidekiq processes
log "Stopping any existing Glitch Cube processes..."
pkill -f "ruby app.rb" || true
pkill -f "sidekiq" || true
sleep 2

# Start the application using bin/prod (handles both Sinatra and Sidekiq)
log_info "Starting Glitch Cube application using bin/prod..."
export RACK_ENV=production

# Use bin/prod which starts both Sinatra and Sidekiq in production mode
cd "$GLITCHCUBE_DIR"
RACK_ENV=production "$ASDF" exec ./bin/prod > "$GLITCHCUBE_DIR/logs/glitchcube.log" 2>&1 &
GLITCHCUBE_PID=$!

# Give it time to start
sleep 10

# Check if Sinatra is responding
if "$CURL" -s -o /dev/null -w "%{http_code}" "http://localhost:4567/health" | grep -q "200"; then
    log_success "Glitch Cube API is running on port 4567"
    log_success "Glitch Cube PID: $GLITCHCUBE_PID"
else
    log_error "Glitch Cube API failed to start"
    log "Check logs at $GLITCHCUBE_DIR/logs/glitchcube.log"
fi

# 7. Final status check
log "========================================="
log "Service Status Summary:"
log "========================================="

# Redis status
"$REDIS_CLI" ping > /dev/null 2>&1 && log_success "Redis: Running" || log_error "Redis: Not running"

# PostgreSQL status
"$PG_ISREADY" -q 2>/dev/null && log_success "PostgreSQL: Running" || log_error "PostgreSQL: Not running"

# Home Assistant status
"$CURL" -s -o /dev/null -w "%{http_code}" "http://glitch.local:8123" | grep -q "200\|401" && \
    log_success "Home Assistant: Running at glitch.local" || log_error "Home Assistant: Not responding"

# Glitch Cube API status
"$CURL" -s -o /dev/null -w "%{http_code}" "http://localhost:4567/health" | grep -q "200" && \
    log_success "Glitch Cube API: Running on port 4567" || log_error "Glitch Cube API: Not responding"

log "========================================="
log "Startup sequence complete"
log "========================================="