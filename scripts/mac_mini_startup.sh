#!/bin/bash

# Glitch Cube Mac Mini Startup Script
# This script ensures all required services are running on boot/reboot
# Install as LaunchDaemon or LaunchAgent for automatic startup

set -e

# Configuration
GLITCHCUBE_DIR="/Users/eristmini/glitch/glitchcube"
HASS_VM_IP="192.168.1.100"  # Update with actual VM IP
HASS_VM_NAME="Home Assistant"  # VMware VM name
LOG_FILE="/Users/eristmini/glitch/startup.log"
MAX_RETRIES=30
RETRY_DELAY=10

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
    brew services start redis
    sleep 3
    
    # Verify Redis started
    if redis-cli ping > /dev/null 2>&1; then
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
if ! pg_isready -q 2>/dev/null; then
    log "PostgreSQL not running. Starting PostgreSQL..."
    brew services start postgresql@14  # Adjust version if needed
    sleep 5
    
    # Wait for PostgreSQL to be ready
    for i in {1..10}; do
        if pg_isready -q 2>/dev/null; then
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
log_info "Checking VMware Fusion..."
if ! pgrep -x "vmware-vmx" > /dev/null; then
    log "Starting VMware Fusion..."
    open -a "VMware Fusion"
    sleep 10
fi

# 4. Start Home Assistant VM if not running
log_info "Checking Home Assistant VM..."
# Check if VM is running using vmrun
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
if [ -f "$VMRUN" ]; then
    # List running VMs and check for Home Assistant
    if ! "$VMRUN" list | grep -q "$HASS_VM_NAME"; then
        log "Starting Home Assistant VM..."
        # Find the VM file (adjust path as needed)
        VM_PATH="/Users/eristmini/Virtual Machines.localized/${HASS_VM_NAME}.vmwarevm/${HASS_VM_NAME}.vmx"
        if [ -f "$VM_PATH" ]; then
            "$VMRUN" start "$VM_PATH" nogui
            sleep 20
        else
            log_error "VM file not found at $VM_PATH"
            log "Please update VM_PATH in this script"
        fi
    else
        log_success "Home Assistant VM already running"
    fi
fi

# 5. Wait for Home Assistant to be accessible
log_info "Waiting for Home Assistant to respond..."
HASS_UP=false
for i in $(seq 1 $MAX_RETRIES); do
    if curl -s -o /dev/null -w "%{http_code}" "http://${HASS_VM_IP}:8123" | grep -q "200\|401"; then
        HASS_UP=true
        log_success "Home Assistant is responding at ${HASS_VM_IP}:8123"
        break
    fi
    
    log "Attempt $i/$MAX_RETRIES: Home Assistant not ready yet..."
    sleep $RETRY_DELAY
done

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
    bundle check || bundle install
fi

# Kill any existing foreman processes
log "Stopping any existing Glitch Cube processes..."
pkill -f "foreman start" || true
sleep 2

# Start the application with foreman
log_info "Starting Glitch Cube with foreman..."
export RACK_ENV=production
export HASS_VM_IP=$HASS_VM_IP

# Start foreman in background
nohup foreman start > "$GLITCHCUBE_DIR/logs/foreman.log" 2>&1 &
FOREMAN_PID=$!

# Give it time to start
sleep 10

# Check if Sinatra is responding
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:4567/health" | grep -q "200"; then
    log_success "Glitch Cube API is running on port 4567"
    log_success "Foreman PID: $FOREMAN_PID"
else
    log_error "Glitch Cube API failed to start"
    log "Check logs at $GLITCHCUBE_DIR/logs/foreman.log"
fi

# 7. Final status check
log "========================================="
log "Service Status Summary:"
log "========================================="

# Redis status
redis-cli ping > /dev/null 2>&1 && log_success "Redis: Running" || log_error "Redis: Not running"

# PostgreSQL status
pg_isready -q 2>/dev/null && log_success "PostgreSQL: Running" || log_error "PostgreSQL: Not running"

# Home Assistant status
curl -s -o /dev/null -w "%{http_code}" "http://${HASS_VM_IP}:8123" | grep -q "200\|401" && \
    log_success "Home Assistant: Running at ${HASS_VM_IP}" || log_error "Home Assistant: Not responding"

# Glitch Cube API status
curl -s -o /dev/null -w "%{http_code}" "http://localhost:4567/health" | grep -q "200" && \
    log_success "Glitch Cube API: Running on port 4567" || log_error "Glitch Cube API: Not responding"

log "========================================="
log "Startup sequence complete"
log "========================================="