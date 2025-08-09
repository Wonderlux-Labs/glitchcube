# Rake Tasks Documentation

## Core Application Tasks

### Running the Application
- `rake run` - Run the application directly (uses WEBrick)
- `rake sidekiq` - Start Sidekiq background job processor
- `rake console` or `rake c` - Open interactive console with app loaded

### Testing
- `rake spec` - Run RSpec test suite (default task)

### Routes
- `rake routes` - Display all application routes with handlers and views

## Database Tasks

### Standard ActiveRecord Tasks
- `rake db:create` - Create the database
- `rake db:migrate` - Run pending migrations
- `rake db:rollback` - Rollback last migration
- `rake db:seed` - Load seed data
- `rake db:reset` - Drop, create, migrate and seed

### Location Data (Burning Man)
- `rake db:seed_locations` - Seed location data if not present (idempotent)
- `rake db:setup_locations` - Download GIS data and seed locations
- `rake setup_locations` - Alias for db:setup_locations

### PostGIS Setup
- `rake postgis:setup` - Setup PostGIS extensions and spatial data

### GIS Data Import
- `rake import:gis_data` - Import GIS data files

## Deployment Tasks

### Mac Mini Deployment
- `rake deploy:push["commit message"]` - Push to production (commit → GitHub → Mac Mini)
- `rake deploy:quick` - Quick push with timestamp message
- `rake deploy:pull` - Manual pull from GitHub (run on Mac Mini)
- `rake deploy:check` - Check for updates from GitHub

### Host Deployment
- `rake host:deploy` - Deploy to host system

### Home Assistant
- `rake hass:deploy` - Deploy Home Assistant configuration

### Configuration Sync
- `rake sync:config` - Synchronize configuration files

## Maintenance Tasks

### Health Checks
- `rake health:check` - Check service health status

### Logs
- `rake logs:cleanup` - Clean up log files older than 7 days

### Backups
- `rake backup:create` - Create timestamped backup of data
- `rake backup:list` - List available backups

## Proactive Tasks
- `rake proactive:*` - Various proactive interaction tasks (see lib/tasks/proactive.rake)

## Script Runner
- `rake run:script` - Run arbitrary scripts

## Deprecated Tasks
The following tasks have been removed as we no longer use these technologies:

### Docker (moved to docker-deprecated/)
- ~~rake docker:status~~
- ~~rake docker:logs~~
- ~~rake docker:restart~~
- ~~rake docker:restart_service~~
- ~~rake docker:update~~

### Puma (now using WEBrick)
- ~~rake puma~~ - Previously ran with Puma server, now uses WEBrick via `rake run`

## Notes
- Most database tasks are hooked to automatically seed location data when appropriate
- The application now runs on Mac Mini hardware instead of Raspberry Pi/Docker
- Configuration uses sinatra-contrib for simplified setup