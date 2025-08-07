#!/bin/bash

# Glitch Cube Restart/Recovery Script
# Can be triggered manually, via API, or automatically by monitoring systems

set -e

# Configuration
GLITCHCUBE_DIR="/Users/eristmini/glitch/glitchcube"
HASS_VM_IP="${HASS_VM_IP:-192.168.1.100}"
LOG_FILE="/Users/eristmini/glitch/restart.log"
RESTART_REASON="${1:-manual}"  # Pass reason as first argument
RESTART_LEVEL="${2:-soft}"     # soft, hard, or nuclear

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$RESTART_REASON] $1" | tee -a "$LOG_FILE"
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

# Send notification to Home Assistant
notify_ha() {
    local message=$1
    local level=${2:-info}  # info, warning, error
    
    if [ -n "$HASS_VM_IP" ]; then
        curl -X POST "http://${HASS_VM_IP}:8123/api/webhook/glitchcube_restart" \
            -H "Content-Type: application/json" \
            -d "{\"message\": \"$message\", \"level\": \"$level\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
            2>/dev/null || true
    fi
}

# Function to stop a service gracefully
stop_service() {
    local service_name=$1
    local stop_command=$2
    local kill_pattern=$3
    
    log_info "Stopping $service_name..."
    
    # Try graceful stop first
    eval "$stop_command" 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    if [ -n "$kill_pattern" ]; then
        pkill -f "$kill_pattern" 2>/dev/null || true
        sleep 1
    fi
    
    log_success "$service_name stopped"
}

# Start logging
log "========================================="
log "Glitch Cube Restart Initiated"
log "Restart Level: $RESTART_LEVEL"
log "Reason: $RESTART_REASON"
log "========================================="

# Notify Home Assistant about restart
notify_ha "Glitch Cube restart initiated: $RESTART_REASON (Level: $RESTART_LEVEL)" "warning"

# SOFT RESTART - Just the Glitch Cube application
if [ "$RESTART_LEVEL" = "soft" ]; then
    log_info "Performing SOFT restart (Glitch Cube only)..."
    
    # Stop Glitch Cube
    stop_service "Foreman" "pkill -TERM -f 'foreman start'" "foreman start"
    stop_service "Puma" "pkill -TERM -f puma" "puma"
    stop_service "Sidekiq" "pkill -TERM -f sidekiq" "sidekiq"
    
    # Clear any stale PID files
    rm -f "$GLITCHCUBE_DIR/tmp/pids/*.pid" 2>/dev/null || true
    
    # Wait a moment
    sleep 3
    
    # Restart Glitch Cube
    log_info "Starting Glitch Cube..."
    cd "$GLITCHCUBE_DIR"
    export RACK_ENV=production
    nohup foreman start > "$GLITCHCUBE_DIR/logs/foreman.log" 2>&1 &
    
    sleep 5
    
    # Verify it's running
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:4567/health" | grep -q "200"; then
        log_success "Glitch Cube restarted successfully"
        notify_ha "Glitch Cube soft restart completed successfully" "info"
    else
        log_error "Glitch Cube failed to restart - trying hard restart"
        RESTART_LEVEL="hard"
    fi
fi

# HARD RESTART - All services except VMware
if [ "$RESTART_LEVEL" = "hard" ]; then
    log_info "Performing HARD restart (all services except VMware)..."
    
    # Stop Glitch Cube
    stop_service "Foreman" "pkill -TERM -f 'foreman start'" "foreman start"
    stop_service "Puma" "pkill -TERM -f puma" "puma"
    stop_service "Sidekiq" "pkill -TERM -f sidekiq" "sidekiq"
    
    # Restart Redis
    log_info "Restarting Redis..."
    brew services restart redis
    sleep 3
    
    # Verify Redis
    if ! redis-cli ping > /dev/null 2>&1; then
        log_error "Redis failed to restart"
        brew services stop redis
        sleep 2
        brew services start redis
        sleep 3
    fi
    
    # Clear Redis queues if they're stuck
    log_info "Clearing stuck Redis queues..."
    redis-cli <<EOF
DEL glitchcube:queue:critical
DEL glitchcube:queue:default  
DEL glitchcube:queue:low
DEL glitchcube:dead
EOF
    
    # Restart PostgreSQL
    log_info "Restarting PostgreSQL..."
    brew services restart postgresql@14
    sleep 5
    
    # Verify PostgreSQL
    if ! pg_isready -q 2>/dev/null; then
        log_error "PostgreSQL failed to restart"
        brew services stop postgresql@14
        sleep 2
        brew services start postgresql@14
        sleep 5
    fi
    
    # Clear any stale files
    rm -f "$GLITCHCUBE_DIR/tmp/pids/*.pid" 2>/dev/null || true
    rm -f "$GLITCHCUBE_DIR/tmp/cache/*.lock" 2>/dev/null || true
    
    # Start Glitch Cube
    log_info "Starting Glitch Cube..."
    cd "$GLITCHCUBE_DIR"
    export RACK_ENV=production
    nohup foreman start > "$GLITCHCUBE_DIR/logs/foreman.log" 2>&1 &
    
    sleep 10
    
    # Verify everything
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:4567/health" | grep -q "200"; then
        log_success "Hard restart completed successfully"
        notify_ha "Glitch Cube hard restart completed successfully" "info"
    else
        log_error "Services failed to restart properly - may need nuclear option"
        notify_ha "Glitch Cube restart failed - manual intervention may be needed" "error"
    fi
fi

# NUCLEAR RESTART - Everything including VMware/Home Assistant
if [ "$RESTART_LEVEL" = "nuclear" ]; then
    log_info "Performing NUCLEAR restart (full system restart)..."
    notify_ha "Nuclear restart initiated - Home Assistant will be restarted" "error"
    
    # Stop everything
    stop_service "Foreman" "pkill -TERM -f 'foreman start'" "foreman start"
    stop_service "Puma" "pkill -TERM -f puma" "puma"
    stop_service "Sidekiq" "pkill -TERM -f sidekiq" "sidekiq"
    
    # Stop VMware VMs
    VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
    if [ -f "$VMRUN" ]; then
        log_info "Stopping all VMware VMs..."
        for vm in $("$VMRUN" list | grep -v "Total running VMs"); do
            log_info "Stopping VM: $vm"
            "$VMRUN" stop "$vm" soft 2>/dev/null || "$VMRUN" stop "$vm" hard 2>/dev/null || true
        done
        sleep 10
    fi
    
    # Restart all services
    log_info "Restarting all services..."
    brew services restart redis
    brew services restart postgresql@14
    sleep 5
    
    # Clear everything
    redis-cli FLUSHDB 2>/dev/null || true
    rm -rf "$GLITCHCUBE_DIR/tmp/cache/*" 2>/dev/null || true
    rm -f "$GLITCHCUBE_DIR/tmp/pids/*.pid" 2>/dev/null || true
    
    # Run the full startup script
    log_info "Running full startup sequence..."
    "$GLITCHCUBE_DIR/scripts/mac_mini_startup.sh"
fi

# Final health check
sleep 5
log "========================================="
log "Post-Restart Health Check"
log "========================================="

# Quick health check
HEALTH_GOOD=true

# Check Redis
if redis-cli ping > /dev/null 2>&1; then
    log_success "Redis: Running"
else
    log_error "Redis: Not running"
    HEALTH_GOOD=false
fi

# Check PostgreSQL
if pg_isready -q 2>/dev/null; then
    log_success "PostgreSQL: Running"
else
    log_error "PostgreSQL: Not running"
    HEALTH_GOOD=false
fi

# Check API
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:4567/health" | grep -q "200"; then
    log_success "Glitch Cube API: Running"
else
    log_error "Glitch Cube API: Not running"
    HEALTH_GOOD=false
fi

# Check Sidekiq
if pgrep -f sidekiq > /dev/null; then
    log_success "Sidekiq: Running"
else
    log_error "Sidekiq: Not running"
    HEALTH_GOOD=false
fi

log "========================================="
if [ "$HEALTH_GOOD" = true ]; then
    log_success "Restart completed successfully!"
    notify_ha "All systems recovered and running normally" "info"
    exit 0
else
    log_error "Some services failed to restart properly"
    notify_ha "Restart completed with errors - check logs" "error"
    exit 1
fi