#!/bin/bash

# Glitch Cube Mac Mini Startup Script
# This script ensures all required services are running on boot/reboot
# Install as LaunchDaemon or LaunchAgent for automatic startup

set -e

# Source common configuration
source "$(dirname "$0")/common_config.sh"

# Define tool commands - will use PATH for discovery
BREW="brew"
REDIS_CLI="redis-cli"
PG_ISREADY="pg_isready"
CURL="curl"
PSQL="psql"

# Set up Ruby environment explicitly (avoid shell integration issues)
cd "$GLITCHCUBE_DIR"

# Use direct Ruby paths instead of asdf for reliability in LaunchAgent
export RUBY_PATH="$HOME/.asdf/installs/ruby/3.4.1/bin"
export BREW_PATH="/opt/homebrew/bin"
export BREW_SBIN_PATH="/opt/homebrew/sbin"
export PATH="$RUBY_PATH:$BREW_PATH:$BREW_SBIN_PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export GEM_HOME="$HOME/.asdf/installs/ruby/3.4.1/lib/ruby/gems/3.4.0"
export GEM_PATH="$GEM_HOME"

# Verify Ruby environment
log "Verifying Ruby environment..."
if [ -f "$RUBY_PATH/ruby" ]; then
    log "Ruby version: $($RUBY_PATH/ruby --version)"
    log "Ruby location: $RUBY_PATH/ruby"
else
    log_error "Ruby not found at $RUBY_PATH/ruby"
    exit 1
fi

if [ -f "$RUBY_PATH/bundle" ]; then
    log "Bundle version: $($RUBY_PATH/bundle --version)"
    log "Bundle location: $RUBY_PATH/bundle"
else
    log_error "Bundle not found at $RUBY_PATH/bundle"
    exit 1
fi
LOG_FILE="$LOG_DIR/startup.log"
INITIAL_WAIT=60  # Wait 60 seconds before first attempt
MAX_RETRIES=30  # 30 attempts after initial wait
RETRY_DELAY=10  # 10 seconds between attempts

# Ensure log directory exists
mkdir -p "$LOG_DIR"
mkdir -p "$GLITCHCUBE_DIR/logs"

# Start logging
log "========================================="
log "Starting Glitch Cube Services"
log "========================================="

# Robust service dependency management function
wait_for_service() {
    local service=$1
    local check_cmd=$2
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for $service to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if eval "$check_cmd" >/dev/null 2>&1; then
            log_success "$service is ready"
            return 0
        fi
        log "Attempt $attempt/$max_attempts: $service not ready, waiting..."
        sleep 2
        ((attempt++))
    done
    
    log_error "$service failed to start within timeout"
    return 1
}

# 1. Check and start Redis
if ! "$REDIS_CLI" ping 2>/dev/null | grep -q PONG; then
    log "Redis not responding. Starting Redis..."
    "$BREW" services restart redis
fi
wait_for_service "Redis" "$REDIS_CLI ping | grep -q PONG" || exit 1

# 2. Check and start PostgreSQL
if ! "$PG_ISREADY" -h localhost -p 5432 -q 2>/dev/null; then
    log "PostgreSQL not running. Starting PostgreSQL..."
    "$BREW" services restart postgresql@16
fi
wait_for_service "PostgreSQL" "$PG_ISREADY -h localhost -p 5432 -q" || exit 1

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

# First check if HA is already up (try Tailscale first, then .local)
HASS_URL="http://${CURRENT_HASS_HOST}:8123"
if "$CURL" -s -o /dev/null -w "%{http_code}" "$HASS_URL" | grep -q "200\|401"; then
    HASS_UP=true
    log_success "Home Assistant is already responding at $CURRENT_HASS_HOST:8123"
else
    log_info "Home Assistant not ready, waiting $INITIAL_WAIT seconds..."
    sleep $INITIAL_WAIT
    
    for i in $(seq 1 $MAX_RETRIES); do
        if "$CURL" -s -o /dev/null -w "%{http_code}" "$HASS_URL" | grep -q "200\|401"; then
            HASS_UP=true
            log_success "Home Assistant is responding at $CURRENT_HASS_HOST:8123"
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

# 6. Load environment variables from .env.production if it exists
cd "$GLITCHCUBE_DIR"
if [ -f ".env.production" ]; then
    log "Loading .env.production for database setup..."
    set -a
    source .env.production
    set +a
fi

# Pull latest code from git (if available)
log_info "Checking for code updates..."
if command -v git >/dev/null 2>&1 && [ -d ".git" ]; then
    if git pull --rebase 2>/dev/null; then
        log_success "Code updated from git"
        
        # Run bundle install if Gemfile changed
        log_info "Checking for gem updates..."
        if "$RUBY_PATH/bundle" install --quiet 2>/dev/null; then
            log_success "Gems updated successfully"
        else
            log "Bundle install had issues but continuing..."
        fi
    else
        log "Git pull skipped or no updates available"
    fi
else
    log "Git not available or not a git repository"
fi

# Run pending migrations with retry logic
run_migrations() {
    log_info "Checking for pending database migrations..."
    
    # Ensure database exists first
    "$RUBY_PATH/bundle" exec rake db:create 2>/dev/null || true
    
    # Run migrations with retry logic
    local max_retries=3
    local retry=1
    
    while [ $retry -le $max_retries ]; do
        if "$RUBY_PATH/bundle" exec rake db:migrate 2>/dev/null; then
            log_success "Database migrations completed successfully"
            return 0
        else
            log "Migration attempt $retry/$max_retries failed"
            if [ $retry -lt $max_retries ]; then
                log "Retrying in 5 seconds..."
                sleep 5
            fi
            ((retry++))
        fi
    done
    
    log_error "Migrations failed after $max_retries attempts - app may handle it"
    return 1
}

run_migrations || true  # Don't exit on migration failure

# 7. Start Glitch Cube application
log_info "Starting Glitch Cube application..."

# Clean up existing processes with proper signal escalation
cleanup_processes() {
    log "Stopping any existing Glitch Cube processes..."
    
    # First try graceful termination with TERM signal
    pkill -TERM -f "ruby.*app\.rb" 2>/dev/null || true
    pkill -TERM -f "sidekiq" 2>/dev/null || true
    pkill -TERM -f "puma.*4567" 2>/dev/null || true
    pkill -TERM -f "thin.*4567" 2>/dev/null || true
    
    # Give processes time to terminate gracefully
    sleep 3
    
    # Check if processes are still running and force kill if necessary
    if pgrep -f "ruby.*app\.rb" > /dev/null 2>&1; then
        log "Force killing remaining Ruby processes..."
        pkill -KILL -f "ruby.*app\.rb" 2>/dev/null || true
    fi
    
    if pgrep -f "sidekiq" > /dev/null 2>&1; then
        log "Force killing remaining Sidekiq processes..."
        pkill -KILL -f "sidekiq" 2>/dev/null || true
    fi
    
    # Ensure port 4567 is free
    if lsof -ti:4567 > /dev/null 2>&1; then
        log "Force killing processes on port 4567..."
        lsof -ti:4567 | xargs kill -9 2>/dev/null || true
    fi
    
    sleep 2
    
    # Verify ports are free
    if lsof -i:4567 > /dev/null 2>&1; then
        log_error "WARNING: Port 4567 still in use after cleanup"
    fi
}

cleanup_processes

# Change to the GlitchCube directory
cd "$GLITCHCUBE_DIR"

# Environment is already loaded above for database setup

# Start the application using bin/prod in the background
log_info "Starting Glitch Cube application using bin/prod..."
export RACK_ENV=production
export APP_ENV=production

# Run bin/prod in background, which handles both Sinatra and Sidekiq
nohup ./bin/prod > "$GLITCHCUBE_DIR/logs/glitchcube.log" 2>&1 &
GLITCHCUBE_PID=$!

# Give it time to start
sleep 10

# Verify application started with health check
verify_app_startup() {
    local max_attempts=10
    local attempt=1
    
    log "Verifying Glitch Cube startup..."
    while [ $attempt -le $max_attempts ]; do
        if "$CURL" -s -o /dev/null -w "%{http_code}" "http://localhost:4567/health" | grep -q "200"; then
            log_success "Glitch Cube API is running on port 4567"
            log_success "Glitch Cube PID: $GLITCHCUBE_PID"
            
            # Store PID for monitoring
            echo $GLITCHCUBE_PID > "$GLITCHCUBE_DIR/logs/glitchcube.pid"
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts: Waiting for app to respond..."
        sleep 3
        ((attempt++))
    done
    
    log_error "Glitch Cube API failed to start after $max_attempts attempts"
    log "Check logs at $GLITCHCUBE_DIR/logs/glitchcube.log"
    
    # Show last few lines of log for debugging
    if [ -f "$GLITCHCUBE_DIR/logs/glitchcube.log" ]; then
        log "Last 10 lines of application log:"
        tail -10 "$GLITCHCUBE_DIR/logs/glitchcube.log" | while read line; do
            log "  $line"
        done
    fi
    
    return 1
}

verify_app_startup

# 8. Final status check
log "========================================="
log "Service Status Summary:"
log "========================================="

# Redis status
"$REDIS_CLI" ping > /dev/null 2>&1 && log_success "Redis: Running" || log_error "Redis: Not running"

# PostgreSQL status
"$PG_ISREADY" -q 2>/dev/null && log_success "PostgreSQL: Running" || log_error "PostgreSQL: Not running"

# Home Assistant status
"$CURL" -s -o /dev/null -w "%{http_code}" "http://${CURRENT_HASS_HOST}:8123" | grep -q "200\|401" && \
    log_success "Home Assistant: Running at $CURRENT_HASS_HOST" || log_error "Home Assistant: Not responding"

# Glitch Cube API status
"$CURL" -s -o /dev/null -w "%{http_code}" "http://localhost:4567/health" | grep -q "200" && \
    log_success "Glitch Cube API: Running on port 4567" || log_error "Glitch Cube API: Not responding"

log "========================================="
log "Startup sequence complete"
log "========================================="