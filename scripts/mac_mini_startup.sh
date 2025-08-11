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
    "$BREW" services start postgresql@16  # Adjust version if needed
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

# 6. Database Setup and Migration
log_info "Setting up database..."
cd "$GLITCHCUBE_DIR"

# Set up DATABASE_URL if not already set
if [ -z "$DATABASE_URL" ]; then
    # Construct DATABASE_URL from .env.production defaults
    DATABASE_HOST=${DATABASE_HOST:-localhost}
    DATABASE_PORT=${DATABASE_PORT:-5432}
    DATABASE_USER=${DATABASE_USER:-postgres}
    DATABASE_PASSWORD=${DATABASE_PASSWORD:-postgres}  # No password for local PostgreSQL
    DATABASE_NAME=${DATABASE_NAME:-glitchcube_production}
    
    # Construct URL with or without password
    if [ -n "$DATABASE_PASSWORD" ]; then
        export DATABASE_URL="postgresql://${DATABASE_USER}:${DATABASE_PASSWORD}@${DATABASE_HOST}:${DATABASE_PORT}/${DATABASE_NAME}"
    else
        export DATABASE_URL="postgresql://${DATABASE_USER}@${DATABASE_HOST}:${DATABASE_PORT}/${DATABASE_NAME}"
    fi
    log "Constructed DATABASE_URL from environment variables"
fi

log "Using DATABASE_URL: ${DATABASE_URL}"

# Wait for database to be ready with timeout
log "Waiting for database to be ready..."
DB_READY=false
for i in $(seq 1 30); do
    if "$PG_ISREADY" -d "$DATABASE_URL" -q 2>/dev/null; then
        DB_READY=true
        log_success "Database is ready"
        break
    fi
    log "Database not ready yet, attempt $i/30..."
    sleep 2
done

if [ "$DB_READY" = false ]; then
    log_error "Database failed to become ready after 60 seconds"
    exit 1
fi

# Ensure dependencies are installed first
if [ -f "Gemfile" ]; then
    log "Installing/checking Ruby dependencies..."
    "$RUBY_PATH/bundle" check || "$RUBY_PATH/bundle" install
fi

# Create database if it doesn't exist (idempotent)
log "Ensuring database exists..."
if "$RUBY_PATH/bundle" exec rake db:create 2>/dev/null; then
    log_success "Database creation successful or already exists"
else
    log_error "Database creation failed"
    exit 1
fi

# Ensure PostGIS extension is available
log "Checking PostGIS extension availability..."
if ! "$PSQL" -d "$DATABASE_NAME" -c "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null; then
    log "PostGIS extension not available, attempting to install..."
    # Try to reinstall PostGIS and restart PostgreSQL
    "$BREW" reinstall postgis
    "$BREW" services restart postgresql@16
    sleep 5
    
    # Try again
    if "$PSQL" -d "$DATABASE_NAME" -c "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null; then
        log_success "PostGIS extension installed successfully"
    else
        log_error "Failed to install PostGIS extension - migrations may fail"
        # Don't exit here, let the migration fail and handle it gracefully
    fi
else
    log_success "PostGIS extension is available"
fi

# Run database migrations (idempotent)
log "Running database migrations..."
if "$RUBY_PATH/bundle" exec rake db:migrate; then
    log_success "Database migrations completed successfully"
else
    log_error "Database migrations failed"
    exit 1
fi

# 7. Start Glitch Cube application
log_info "Starting Glitch Cube application..."

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
RACK_ENV=production ./bin/prod > "$GLITCHCUBE_DIR/logs/glitchcube.log" 2>&1 &
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