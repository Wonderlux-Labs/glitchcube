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
        docker-compose -f docker-compose.yml -f docker-compose.production.yml stop
        SERVICES_STOPPED=true
    fi
fi

# Backup data directories
backup_directory "data/$ENVIRONMENT/glitchcube" "glitchcube_data"
backup_directory "data/$ENVIRONMENT/context_documents" "context_documents"

# Backup Redis if running
if docker ps | grep -q glitchcube_redis; then
    echo "📦 Backing up Redis..."
    docker exec glitchcube_redis redis-cli BGSAVE
    sleep 2
    docker cp glitchcube_redis:/data/dump.rdb "$BACKUP_DIR/redis_${ENVIRONMENT}_${TIMESTAMP}.rdb"
    echo "✅ Redis backed up successfully"
fi

# Backup PostgreSQL if running
if docker ps | grep -q glitchcube_postgres; then
    echo "📦 Backing up PostgreSQL..."
    docker exec glitchcube_postgres pg_dump -U glitchcube glitchcube > "$BACKUP_DIR/postgres_${ENVIRONMENT}_${TIMESTAMP}.sql"
    echo "✅ PostgreSQL backed up successfully"
fi

# Restart services if they were stopped
if [ "$SERVICES_STOPPED" = true ]; then
    echo "🚀 Restarting services..."
    docker-compose -f docker-compose.yml -f docker-compose.production.yml start
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