# MariaDB Setup Guide

This guide covers setting up MariaDB as the database backend for Glitch Cube, replacing SQLite for better performance and Home Assistant integration.

## Overview

MariaDB is preferred over PostgreSQL because:
- Home Assistant officially recommends MariaDB for logging and event storage
- Better performance for IoT device data
- Shared database instance can serve both applications
- Superior UTF-8 support for international characters

## Quick Start

### 1. Backup Existing Data (CRITICAL)

```bash
# Always backup first!
./scripts/backup-sqlite-to-mariadb.sh
```

This script:
- Backs up all SQLite databases with timestamps
- Creates SQL dumps for manual inspection
- Provides rollback instructions

### 2. Start MariaDB Service

```bash
# Start MariaDB container
docker-compose --profile mariadb up -d mariadb

# Check initialization logs
docker logs -f glitchcube_mariadb
```

Wait for: `ready for connections` in the logs.

### 3. Enable MariaDB in Configuration

Update your `.env` file:

```bash
# Enable MariaDB
MARIADB_ENABLED=true

# Optional: Override auto-detection
DATABASE_URL=mysql2://glitchcube:glitchcube@localhost:3306/glitchcube?encoding=utf8mb4
```

### 4. Restart Application

```bash
docker-compose restart glitchcube sidekiq
```

## Configuration Options

### Environment Variables

```bash
# Core MariaDB settings
MARIADB_ENABLED=true                    # Enable MariaDB backend
MARIADB_HOST=localhost                  # Database host
MARIADB_PORT=3306                       # Database port
MARIADB_DATABASE=glitchcube            # Database name
MARIADB_USERNAME=glitchcube            # Application user
MARIADB_PASSWORD=glitchcube            # Application password

# Container settings
MYSQL_ROOT_PASSWORD=glitchcube123      # Root password for container
MYSQL_PASSWORD=glitchcube              # Application password (Docker)
```

### Database URL Override

For complete control, use `DATABASE_URL`:

```bash
# Direct MariaDB connection
DATABASE_URL=mysql2://glitchcube:glitchcube@localhost:3306/glitchcube?encoding=utf8mb4

# External MariaDB server
DATABASE_URL=mysql2://user:password@mariadb.example.com:3306/glitchcube?encoding=utf8mb4
```

## Safety Features

### Automatic Fallback

The application includes safety checks:

1. **Data Protection**: Won't migrate if existing SQLite data is detected in production
2. **Test Isolation**: Always uses in-memory SQLite for tests
3. **Graceful Degradation**: Falls back to SQLite if MariaDB is unavailable

### Migration Safety

```ruby
# In config/persistence.rb
unless GlitchCube.config.safe_to_migrate?
  puts "⚠️  Database migration blocked for safety"
  # Uses SQLite fallback
end
```

## Database Schema

MariaDB container creates these databases:

### `glitchcube` Database
- `conversations` - AI conversation history
- `device_status` - Hardware monitoring data
- `session_analytics` - User interaction metrics
- Plus Desiru framework tables (auto-created)

### `homeassistant` Database
- Available for Home Assistant logging
- Shared MariaDB instance for efficiency

## Troubleshooting

### Check MariaDB Status

```bash
# Container status
docker ps | grep mariadb

# Database connectivity
docker exec glitchcube_mariadb mysql -u root -p -e "SHOW DATABASES;"

# Application logs
docker logs glitchcube_app | grep -i database
```

### Common Issues

#### "Access denied for user"
```bash
# Reset passwords
docker exec -it glitchcube_mariadb mysql -u root -p
mysql> ALTER USER 'glitchcube'@'%' IDENTIFIED BY 'glitchcube';
mysql> FLUSH PRIVILEGES;
```

#### "Can't connect to MySQL server"
```bash
# Check if MariaDB is running
docker-compose --profile mariadb ps mariadb

# Restart if needed
docker-compose --profile mariadb restart mariadb
```

#### "Table doesn't exist"
```bash
# Run migrations manually
docker exec glitchcube_app bundle exec ruby -e "
require './app.rb'
GlitchCube::Persistence.configure!
"
```

### Performance Monitoring

```bash
# Check slow queries
docker exec glitchcube_mariadb mysql -u root -p -e "
SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 10;
"

# Connection status
docker exec glitchcube_mariadb mysql -u root -p -e "SHOW STATUS LIKE 'Threads_connected';"
```

## Rollback Procedure

If you need to return to SQLite:

### 1. Stop Services
```bash
docker-compose down
```

### 2. Restore SQLite Data
```bash
# Find your backup
ls data/backups/

# Restore specific backup
cp data/backups/YYYYMMDD_HHMMSS/glitchcube_production.db data/production/glitchcube.db
```

### 3. Disable MariaDB
Update `.env`:
```bash
MARIADB_ENABLED=false
# DATABASE_URL=sqlite://data/production/glitchcube.db  # Or remove entirely
```

### 4. Restart
```bash
docker-compose up -d glitchcube sidekiq
```

## Performance Tuning

### MariaDB Configuration

The container includes optimized settings:

```sql
-- In docker-compose.yml command section:
--character-set-server=utf8mb4
--collation-server=utf8mb4_unicode_ci
--max-connections=250
--innodb-buffer-pool-size=256M
--innodb-log-file-size=64M
--slow-query-log=1
--long-query-time=2
```

### Connection Pooling

For high-traffic scenarios, consider connection pooling:

```ruby
# In config/database.rb (future enhancement)
Sequel.connect(
  mariadb_url,
  max_connections: 10,
  pool_timeout: 5
)
```

## Home Assistant Integration

### Shared Database Benefits

1. **Unified Storage**: Both applications use same MariaDB instance
2. **Cross-Application Queries**: Glitch Cube can analyze HA event data
3. **Efficient Resource Usage**: Single database container
4. **Consistent Backups**: One backup strategy for both apps

### Home Assistant Configuration

In Home Assistant's `configuration.yaml`:

```yaml
recorder:
  db_url: mysql://homeassistant:homeassistant@localhost:3306/homeassistant?charset=utf8mb4
  purge_keep_days: 30
  include:
    domains:
      - sensor
      - binary_sensor
      - device_tracker
```

## Monitoring and Maintenance

### Health Checks

Built-in Docker health check:
```bash
# Check health status
docker inspect glitchcube_mariadb | grep -A 5 Health
```

### Backup Strategy

```bash
# Regular database backup
docker exec glitchcube_mariadb mysqldump -u root -p --all-databases > backup.sql

# Automated backup (add to cron)
docker exec glitchcube_mariadb mysqldump -u root -p glitchcube > daily_backup.sql
```

### Log Management

```bash
# View slow queries
docker exec glitchcube_mariadb tail -f /var/log/mysql/slow.log

# General query log (if enabled)
docker exec glitchcube_mariadb tail -f /var/log/mysql/mysql.log
```

## Next Steps

1. **Monitor Performance**: Check application logs for database performance
2. **Set Up Backups**: Implement regular backup strategy
3. **Test Migration**: Verify all existing functionality works
4. **Home Assistant**: Consider migrating HA to shared MariaDB instance
5. **Connection Pooling**: Implement if needed for performance

## Support

For issues:
1. Check container logs: `docker logs glitchcube_mariadb`
2. Verify configuration: `GlitchCube.config.mariadb_url`
3. Test connection: Use mysql client to connect manually
4. Review backup files: SQL dumps contain schema and data