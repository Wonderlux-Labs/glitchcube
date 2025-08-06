# Deprecated Deployment Files

This folder contains old deployment methods that have been replaced by the new GitHub → Home Assistant → Sinatra deployment system.

## What's Deprecated

**Old Sinatra Routes:**
- `deploy.rb` - Old deployment routes
- `webhook_deploy.rb` - Old webhook implementation

**Old Home Assistant Files:**
- `auto_deploy.yaml` - Old automation
- `deployment.yaml` - Old input helpers
- `glitchcube_deployment.yaml` - Old sensor

**Old Scripts & Docs:**
- `deploy/` - Old deployment scripts
- `deployment.md` - Old deployment documentation
- `mac-mini-vm-deployment.md` - Mac mini specific docs
- `archived_deploy_raspi_script.txt` - Old Raspberry Pi scripts

**Old Tests & Helpers:**
- `deployment_helper.rb` - Old deployment helper functions
- Various spec files for deprecated functionality

## Current Deployment System

The new system uses:
- **GitHub Actions** → **Home Assistant Webhook** → **Sinatra Internal API**
- Files: `/lib/routes/api/deployment.rb`, HA automations, GitHub workflow
- Documentation: `/docs/github-webhook-setup.md`

## Why Deprecated

The old system had multiple approaches and was overly complex for an art installation. The new system is:
- Simpler (no secrets/tokens needed)
- More reliable (goes through Home Assistant which has external access)
- Art installation appropriate (minimal security concerns)
- Single deployment path (less maintenance)

These files are kept for reference but should not be used in the current system.