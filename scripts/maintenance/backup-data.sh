#!/bin/bash
# Backup script for Glitch Cube data
# Creates timestamped backups of all data directories

set -e

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ENVIRONMENT="${1:-production}"

echo "🎲 Glitch Cube Data Backup Script"
echo "================================="
echo "Environment: $ENVIRONMENT"
echo "Timestamp: $TIMESTAMP"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Function to backup a directory
backup_directory() {
    local source=$1
    local name=$2
    
    if [ -d "$source" ]; then
        echo "📦 Backing up $name..."
        tar -czf "$BACKUP_DIR/${name}_${ENVIRONMENT}_${TIMESTAMP}.tar.gz" -C "$(dirname "$source")" "$(basename "$source")"
        echo "✅ $name backed up successfully"
    else
        echo "⚠️  $source not found, skipping..."
    fi
}

# Stop services if backing up production
if [ "$ENVIRONMENT" = "production" ]; then
    read -p "Stop services before backup? (recommended) [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🛑 Stopping services..."
        # Stop Glitch Cube service using launchctl
        launchctl unload ~/Library/LaunchAgents/com.glitchcube.startup.plist 2>/dev/null || true
        pkill -f "ruby app.rb" 2>/dev/null || true
        pkill -f sidekiq 2>/dev/null || true
        sleep 2
        SERVICES_STOPPED=true
    fi
fi

# Backup data directories
backup_directory "data/$ENVIRONMENT/glitchcube" "glitchcube_data"
backup_directory "data/$ENVIRONMENT/context_documents" "context_documents"

# Backup Redis if running locally
if command -v redis-cli &> /dev/null; then
    if redis-cli ping &> /dev/null; then
        echo "📦 Backing up Redis..."
        redis-cli BGSAVE
        sleep 2
        # Default Redis dump location on macOS/Linux
        REDIS_DUMP="/usr/local/var/db/redis/dump.rdb"
        if [ -f "$REDIS_DUMP" ]; then
            cp "$REDIS_DUMP" "$BACKUP_DIR/redis_${ENVIRONMENT}_${TIMESTAMP}.rdb"
            echo "✅ Redis backed up successfully"
        else
            echo "⚠️  Redis dump file not found at expected location"
        fi
    fi
fi

# Backup PostgreSQL if configured
if [ -n "$DATABASE_URL" ]; then
    echo "📦 Backing up PostgreSQL..."
    # Extract connection info from DATABASE_URL if needed
    pg_dump "$DATABASE_URL" > "$BACKUP_DIR/postgres_${ENVIRONMENT}_${TIMESTAMP}.sql" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ PostgreSQL backed up successfully"
    else
        echo "⚠️  PostgreSQL backup skipped (not configured or accessible)"
    fi
fi

# Restart services if they were stopped
if [ "$SERVICES_STOPPED" = true ]; then
    echo "🚀 Restarting services..."
    # Restart Glitch Cube service using launchctl
    launchctl load ~/Library/LaunchAgents/com.glitchcube.startup.plist 2>/dev/null || true
    # The launchd service will automatically restart the app
    echo "✅ Services restarted via launchctl"
fi

# Show backup summary
echo ""
echo "📊 Backup Summary"
echo "================"
echo "Location: $BACKUP_DIR"
echo "Files created:"
ls -lh "$BACKUP_DIR"/*_${ENVIRONMENT}_${TIMESTAMP}* 2>/dev/null || echo "No files created"

# Cleanup old backups (keep last 7 days)
if [ "$ENVIRONMENT" = "production" ]; then
    echo ""
    echo "🧹 Cleaning up old backups..."
    find "$BACKUP_DIR" -name "*_production_*.tar.gz" -mtime +7 -delete
    find "$BACKUP_DIR" -name "*_production_*.rdb" -mtime +7 -delete
    find "$BACKUP_DIR" -name "*_production_*.sql" -mtime +7 -delete
    echo "✅ Old backups cleaned up"
fi

echo ""
echo "✨ Backup complete!"