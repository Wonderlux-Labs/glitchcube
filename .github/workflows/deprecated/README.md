# Deprecated GitHub Workflows

These workflows have been moved here because they were causing conflicts with the current deployment system.

## Issue
All of these workflows were triggering on `push` to `main` branch, causing **multiple simultaneous deployments** for every commit.

## Current Active Workflows
- `deploy-on-push.yml` - **Modern deployment** via Sinatra API
- `test.yml` - Test suite
- `lint.yml` - Code linting

## Deprecated Workflows

### `deploy.yml`
- **Deprecated**: Old deployment approach
- **Replaced by**: `deploy-on-push.yml` with Sinatra API

### `deploy-conditional.yml`
- **Deprecated**: Conditional deployment logic
- **Replaced by**: Deployment logic moved to Sinatra API

### `notify-deploy.yml` 
- **Deprecated**: Old approach using HA `input_boolean`
- **Replaced by**: Direct webhook to Sinatra API

### `deploy-mac-mini.yml`
- **Deprecated**: VM-specific deployment
- **Replaced by**: Unified deployment via current API
- **Note**: Used secret `HA_WEBHOOK_URL` but triggered on same branch

## Migration Notes
The current deployment flow is:
1. **GitHub Action** (`deploy-on-push.yml`) sends webhook on push to main
2. **Home Assistant** receives webhook and forwards to Sinatra API
3. **Sinatra API** (`/api/v1/deploy/internal`) executes deployment
4. **Deployment includes**: git pull + config sync + service restart

## Recovery
If any of these workflows are needed for specific environments:
1. Move them back to `.github/workflows/`
2. Change the trigger to avoid conflicts (different branch, manual only, etc.)
3. Update deployment endpoints to match current API structure

---
*Deprecated on: 2025-08-06*
*Reason: Multiple deployment triggers causing conflicts*