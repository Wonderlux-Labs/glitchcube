#!/bin/bash
# Mac Mini deployment script - pulls latest code and restarts services

set -e

# Source common configuration
source "$(dirname "$0")/common_config.sh"

LOG_FILE="$LOG_DIR/deploy.log"

log "========================================="
log "Starting deployment from GitHub"
log "========================================="

# Navigate to project directory
cd "$GLITCHCUBE_DIR"

# Pull latest code
log "Pulling latest code from GitHub..."
git pull origin main

# Install/update dependencies
log "Checking Ruby dependencies..."
/opt/homebrew/bin/asdf exec bundle check || /opt/homebrew/bin/asdf exec bundle install

# Stop existing services
log "Stopping existing services..."
pkill -f "ruby app.rb" || true
pkill -f "sidekiq" || true
sleep 2

# Start services using bin/prod
log "Starting services with bin/prod..."
export RACK_ENV=production
/opt/homebrew/bin/asdf exec ./bin/prod > "$GLITCHCUBE_DIR/logs/glitchcube.log" 2>&1 &

# Wait and check if services started
sleep 10

# Check if API is responding
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:4567/health" | grep -q "200"; then
    log "✅ Deployment successful - API responding"
else
    log "⚠️  API not responding after deployment"
fi

log "========================================="
log "Deployment complete"
log "========================================="