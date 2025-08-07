# ⚠️ DEPRECATED - DO NOT USE

**These deployment files are outdated and kept for historical reference only.**

## Current Deployment System

For the current deployment setup, see:
- **📚 Main Documentation**: [/docs/DEPLOYMENT.md](/docs/DEPLOYMENT.md)
- **🔧 Rake Tasks**: 
  - `/lib/tasks/hass_deploy.rake` - Home Assistant VM deployment
  - `/lib/tasks/host_deploy.rake` - Sinatra host deployment
  - `/lib/tasks/sync_config.rake` - Config synchronization
- **🤖 GitHub Actions**: `/.github/workflows/deploy.yml`
- **📡 API Routes**: `/lib/routes/api/deployment.rb`

## What Changed

**Old System** (files in this folder):
- Docker-based deployment
- Raspberry Pi focused
- Complex shell scripts
- Manual SSH commands

**New System** (as of Jan 2025):
- Mac Mini host + VMware VM architecture
- Rake task based deployment
- GitHub Actions with webhook triggers
- Automated startup recovery
- API endpoints for deployment control

## Why These Are Deprecated

- Moved from Docker to native Mac Mini deployment
- Switched from Raspberry Pi to Mac Mini hardware
- Replaced shell scripts with Ruby rake tasks
- Integrated deployment into the app itself (API endpoints)
- Added automatic missed deployment recovery

---
*Last updated: January 2025*