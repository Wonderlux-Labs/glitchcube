#!/bin/bash
# frozen_string_literal: true

# Glitch Cube SQLite to MariaDB Migration Script
# This script safely backs up existing SQLite data and helps migrate to MariaDB

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_ROOT/data/backups/$(date +%Y%m%d_%H%M%S)"

echo "🔄 Glitch Cube Database Migration Script"
echo "========================================"
echo

# Check if we're in the right directory
if [[ ! -f "$PROJECT_ROOT/app.rb" ]]; then
    echo "❌ Error: Must run from Glitch Cube project root"
    echo "   Current: $(pwd)"
    echo "   Expected: $PROJECT_ROOT"
    exit 1
fi

# Create backup directory
echo "📁 Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Function to backup SQLite file
backup_sqlite() {
    local sqlite_file="$1"
    local backup_name="$2"
    
    if [[ -f "$sqlite_file" ]]; then
        echo "💾 Backing up $sqlite_file..."
        cp "$sqlite_file" "$BACKUP_DIR/$backup_name"
        
        # Also create a SQL dump for easier inspection/migration
        if command -v sqlite3 >/dev/null 2>&1; then
            echo "📝 Creating SQL dump: $backup_name.sql"
            sqlite3 "$sqlite_file" .dump > "$BACKUP_DIR/$backup_name.sql"
        fi
        
        echo "✅ Backup complete: $BACKUP_DIR/$backup_name"
        return 0
    else
        echo "⚠️  No SQLite file found at: $sqlite_file"
        return 1
    fi
}

# Look for existing SQLite databases
echo "🔍 Searching for existing SQLite databases..."
echo

FOUND_DATA=false

# Check common SQLite locations
if backup_sqlite "$PROJECT_ROOT/data/glitchcube.db" "glitchcube_dev.db"; then
    FOUND_DATA=true
fi

if backup_sqlite "$PROJECT_ROOT/data/production/glitchcube.db" "glitchcube_production.db"; then
    FOUND_DATA=true
fi

# Check for any .db files in data directories
find "$PROJECT_ROOT/data" -name "*.db" -type f 2>/dev/null | while IFS= read -r db_file; do
    relative_path="${db_file#$PROJECT_ROOT/}"
    backup_name="$(basename "$db_file")"
    backup_sqlite "$db_file" "found_$backup_name"
    FOUND_DATA=true
done

echo
if [[ "$FOUND_DATA" == "true" ]]; then
    echo "✅ Database backup completed successfully!"
    echo "📁 Backup location: $BACKUP_DIR"
    echo
    echo "🔧 Next steps to enable MariaDB:"
    echo "1. Start MariaDB service: docker-compose --profile mariadb up -d mariadb"
    echo "2. Wait for MariaDB to initialize (check logs: docker logs glitchcube_mariadb)"
    echo "3. Enable MariaDB in .env: MARIADB_ENABLED=true"
    echo "4. Optional: Set DATABASE_URL to override auto-detection"
    echo "5. Restart application: docker-compose restart glitchcube"
    echo
    echo "⚠️  IMPORTANT: Keep these backups until you verify MariaDB is working correctly!"
    echo "   Restore command: cp $BACKUP_DIR/glitchcube_*.db /path/to/original/location"
else
    echo "ℹ️  No existing SQLite databases found - safe to proceed with MariaDB setup"
    echo
    echo "🚀 To enable MariaDB from scratch:"
    echo "1. Start MariaDB: docker-compose --profile mariadb up -d mariadb"
    echo "2. Enable in .env: MARIADB_ENABLED=true"
    echo "3. Restart application: docker-compose restart glitchcube"
fi

echo
echo "📖 For manual data migration, see SQL dumps in: $BACKUP_DIR/*.sql"
echo "🔍 Check MariaDB status: docker exec glitchcube_mariadb mysql -u root -p -e 'SHOW DATABASES;'"