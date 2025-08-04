#!/bin/bash
# Restore script for Glitch Cube data
# Restores data from backup files

set -e

BACKUP_DIR="${BACKUP_DIR:-./backups}"
ENVIRONMENT="${1:-production}"

echo "🎲 Glitch Cube Data Restore Script"
echo "==================================="
echo "Environment: $ENVIRONMENT"
echo ""

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Backup directory not found: $BACKUP_DIR"
    exit 1
fi

# List available backups
echo "📋 Available backups:"
echo ""
ls -lh "$BACKUP_DIR"/*_${ENVIRONMENT}_*.tar.gz 2>/dev/null || {
    echo "No backups found for environment: $ENVIRONMENT"
    exit 1
}

echo ""
read -p "Enter the timestamp to restore (e.g., 20240104_120000): " TIMESTAMP

if [ -z "$TIMESTAMP" ]; then
    echo "❌ No timestamp provided"
    exit 1
fi

# Confirm restoration
echo ""
echo "⚠️  WARNING: This will overwrite existing data!"
echo "Restoring from timestamp: $TIMESTAMP"
read -p "Continue? [y/N] " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restoration cancelled"
    exit 0
fi

# Stop services
echo "🛑 Stopping services..."
if [ "$ENVIRONMENT" = "production" ]; then
    docker-compose -f docker-compose.yml -f docker-compose.production.yml stop
else
    docker-compose stop
fi

# Function to restore a directory
restore_directory() {
    local backup_file=$1
    local target_dir=$2
    
    if [ -f "$backup_file" ]; then
        echo "📦 Restoring from $(basename "$backup_file")..."
        mkdir -p "$(dirname "$target_dir")"
        tar -xzf "$backup_file" -C "$(dirname "$target_dir")"
        echo "✅ Restored successfully"
    else
        echo "⚠️  Backup file not found: $backup_file"
    fi
}

# Restore data directories
restore_directory "$BACKUP_DIR/glitchcube_data_${ENVIRONMENT}_${TIMESTAMP}.tar.gz" "data/$ENVIRONMENT/glitchcube"
restore_directory "$BACKUP_DIR/context_documents_${ENVIRONMENT}_${TIMESTAMP}.tar.gz" "data/$ENVIRONMENT/context_documents"

# Restore Redis if backup exists
if [ -f "$BACKUP_DIR/redis_${ENVIRONMENT}_${TIMESTAMP}.rdb" ]; then
    echo "📦 Restoring Redis..."
    docker-compose up -d redis
    sleep 5
    docker cp "$BACKUP_DIR/redis_${ENVIRONMENT}_${TIMESTAMP}.rdb" glitchcube_redis:/data/dump.rdb
    docker-compose restart redis
    echo "✅ Redis restored successfully"
fi

# Restore PostgreSQL if backup exists
if [ -f "$BACKUP_DIR/postgres_${ENVIRONMENT}_${TIMESTAMP}.sql" ]; then
    echo "📦 Restoring PostgreSQL..."
    docker-compose up -d postgres
    sleep 10
    docker exec -i glitchcube_postgres psql -U glitchcube glitchcube < "$BACKUP_DIR/postgres_${ENVIRONMENT}_${TIMESTAMP}.sql"
    echo "✅ PostgreSQL restored successfully"
fi

# Start services
echo "🚀 Starting services..."
if [ "$ENVIRONMENT" = "production" ]; then
    docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d
else
    docker-compose up -d
fi

# Wait for services
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Check service status
echo ""
echo "📊 Service Status:"
docker-compose ps

echo ""
echo "✨ Restoration complete!"
echo ""
echo "Please verify:"
echo "1. Services are running correctly"
echo "2. Data has been restored properly"
echo "3. Context documents are accessible"