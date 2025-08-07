#!/bin/bash

# Glitch Cube Health Monitor with Auto-Recovery
# Runs periodically to check health and trigger restarts if needed

# Configuration
GLITCHCUBE_DIR="/Users/eristmini/glitch/glitchcube"
HASS_VM_IP="${HASS_VM_IP:-192.168.1.100}"
API_PORT="${API_PORT:-4567}"
LOG_FILE="/Users/eristmini/glitch/monitor.log"
STATE_FILE="/Users/eristmini/glitch/monitor.state"
MAX_FAILURES=3  # Number of consecutive failures before restart
RESTART_COOLDOWN=300  # Minimum seconds between restarts

# Load previous state
if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE"
else
    CONSECUTIVE_FAILURES=0
    LAST_RESTART_TIME=0
fi

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Update state file
update_state() {
    cat > "$STATE_FILE" << EOF
CONSECUTIVE_FAILURES=$CONSECUTIVE_FAILURES
LAST_RESTART_TIME=$LAST_RESTART_TIME
EOF
}

# Check if enough time has passed since last restart
can_restart() {
    local current_time=$(date +%s)
    local time_since_restart=$((current_time - LAST_RESTART_TIME))
    
    if [ $time_since_restart -gt $RESTART_COOLDOWN ]; then
        return 0
    else
        return 1
    fi
}

# Perform health checks
perform_checks() {
    local failures=0
    local critical_failure=false
    local failure_reasons=""
    
    # Check 1: Redis
    if ! redis-cli ping > /dev/null 2>&1; then
        failures=$((failures + 1))
        failure_reasons="${failure_reasons}Redis down. "
        critical_failure=true
    fi
    
    # Check 2: PostgreSQL
    if ! pg_isready -q 2>/dev/null; then
        failures=$((failures + 1))
        failure_reasons="${failure_reasons}PostgreSQL down. "
        critical_failure=true
    fi
    
    # Check 3: Glitch Cube API
    if ! curl -s --max-time 10 -o /dev/null -w "%{http_code}" "http://localhost:${API_PORT}/health" | grep -q "200"; then
        failures=$((failures + 1))
        failure_reasons="${failure_reasons}API not responding. "
    fi
    
    # Check 4: Sidekiq
    if ! pgrep -f sidekiq > /dev/null; then
        failures=$((failures + 1))
        failure_reasons="${failure_reasons}Sidekiq not running. "
    fi
    
    # Check 5: Memory usage (Mac specific)
    if command -v vm_stat > /dev/null; then
        mem_pressure=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        mem_free_mb=$((mem_pressure * 4096 / 1024 / 1024))
        if [ $mem_free_mb -lt 500 ]; then
            failures=$((failures + 1))
            failure_reasons="${failure_reasons}Low memory (${mem_free_mb}MB free). "
        fi
    fi
    
    # Check 6: Disk space
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 95 ]; then
        failures=$((failures + 1))
        failure_reasons="${failure_reasons}Disk critically full (${disk_usage}%). "
        critical_failure=true
    fi
    
    # Check 7: Redis queue buildup
    if redis-cli ping > /dev/null 2>&1; then
        total_queued=$(redis-cli eval "
            local total = 0
            total = total + redis.call('llen', 'glitchcube:queue:critical')
            total = total + redis.call('llen', 'glitchcube:queue:default')
            total = total + redis.call('llen', 'glitchcube:queue:low')
            return total
        " 0 2>/dev/null || echo "0")
        
        if [ "$total_queued" -gt 100 ]; then
            failures=$((failures + 1))
            failure_reasons="${failure_reasons}Queue buildup (${total_queued} jobs). "
        fi
    fi
    
    # Check 8: Recent errors in logs
    if [ -d "$GLITCHCUBE_DIR/logs" ]; then
        recent_errors=$(tail -n 500 "$GLITCHCUBE_DIR/logs"/*.log 2>/dev/null | grep -c "ERROR\|FATAL\|Exception" || echo "0")
        if [ "$recent_errors" -gt 50 ]; then
            failures=$((failures + 1))
            failure_reasons="${failure_reasons}High error rate (${recent_errors} errors). "
        fi
    fi
    
    # Return results
    echo "$failures|$critical_failure|$failure_reasons"
}

# Main monitoring logic
log "Starting health check..."

# Perform checks
check_result=$(perform_checks)
failures=$(echo "$check_result" | cut -d'|' -f1)
critical=$(echo "$check_result" | cut -d'|' -f2)
reasons=$(echo "$check_result" | cut -d'|' -f3)

if [ "$failures" -eq 0 ]; then
    # Everything is healthy
    if [ "$CONSECUTIVE_FAILURES" -gt 0 ]; then
        log "✓ System recovered - all checks passed"
    else
        log "✓ All systems healthy"
    fi
    CONSECUTIVE_FAILURES=0
    update_state
else
    # We have failures
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    log "⚠ Health check failed ($failures issues): $reasons"
    log "  Consecutive failures: $CONSECUTIVE_FAILURES"
    
    # Determine if we should restart
    should_restart=false
    restart_level="soft"
    
    if [ "$critical" = "true" ]; then
        # Critical failure - restart immediately
        should_restart=true
        restart_level="hard"
        log "✗ Critical failure detected - immediate restart required"
    elif [ "$CONSECUTIVE_FAILURES" -ge "$MAX_FAILURES" ]; then
        # Too many consecutive failures
        should_restart=true
        if [ "$CONSECUTIVE_FAILURES" -ge $((MAX_FAILURES * 2)) ]; then
            restart_level="hard"
        fi
        log "✗ Maximum consecutive failures reached - restart required"
    fi
    
    # Perform restart if needed and cooldown has passed
    if [ "$should_restart" = true ]; then
        if can_restart; then
            log "🔄 Initiating $restart_level restart..."
            
            # Trigger restart
            "$GLITCHCUBE_DIR/scripts/glitchcube_restart.sh" "auto-monitor" "$restart_level"
            
            # Update state
            LAST_RESTART_TIME=$(date +%s)
            CONSECUTIVE_FAILURES=0
            update_state
            
            log "✓ Restart initiated"
        else
            time_remaining=$((RESTART_COOLDOWN - ($(date +%s) - LAST_RESTART_TIME)))
            log "⏳ Restart needed but in cooldown (${time_remaining}s remaining)"
        fi
    fi
    
    update_state
fi

# Log queue sizes for monitoring
if redis-cli ping > /dev/null 2>&1; then
    critical_queue=$(redis-cli llen glitchcube:queue:critical 2>/dev/null || echo "0")
    default_queue=$(redis-cli llen glitchcube:queue:default 2>/dev/null || echo "0")
    low_queue=$(redis-cli llen glitchcube:queue:low 2>/dev/null || echo "0")
    dead_queue=$(redis-cli llen glitchcube:dead 2>/dev/null || echo "0")
    
    if [ "$critical_queue" -gt 0 ] || [ "$default_queue" -gt 10 ] || [ "$low_queue" -gt 20 ] || [ "$dead_queue" -gt 0 ]; then
        log "📊 Queue status: critical=$critical_queue, default=$default_queue, low=$low_queue, dead=$dead_queue"
    fi
fi