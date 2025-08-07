# Glitch Cube Deployment Guide

## 🏗️ Current Architecture

**Production Setup:**
- **Host**: Mac Mini running macOS
- **Sinatra App**: Runs directly on Mac Mini host
- **Home Assistant**: Runs in VMware VM with separate IP address
- **Development**: Local macOS (separate from production)

## 📦 Deployment Methods

### 1. Manual Deployment (From Dev Machine)

#### Quick Commands
```bash
# Deploy Home Assistant config to VM
rake hass:deploy        # Full deploy with backup & restart
rake hass:quick         # Fast sync without restart
rake hass:pull          # Pull config from VM to local

# Deploy Sinatra application
rake host:deploy        # Git pull + bundle + restart
rake host:restart       # Just restart Sinatra
rake host:status        # Check Sinatra status

# Full deployment
rake deploy:full        # Deploy both Sinatra and HA
rake deploy:smart       # Deploy only what changed
rake deploy:check       # See what needs deploying
```

#### Environment Setup
```bash
# First time setup
./scripts/setup_deployment.sh

# Configure your .env.deployment
HASS_VM_HOST=192.168.1.100  # Your VM's IP
HASS_VM_USER=homeassistant   # VM SSH user
```

#### SSH Setup (One-time)
```bash
# Setup passwordless SSH to VM
rake hass:setup_ssh
```

### 2. Automated Deployment (GitHub → Production)

#### Flow
1. **Push to GitHub** (main branch)
2. **GitHub Actions** runs tests (VCR cassettes only, no external API calls)
3. **On green build** → Webhook sent to Home Assistant
4. **Home Assistant** triggers deployment automation
5. **Host system** pulls git and restarts Sinatra
6. **Host system** deploys HA config via SCP to VM
7. **Home Assistant** restarts with new config

#### Automatic Startup Recovery
When the production app starts, it:
- Checks if behind git remote
- If behind, schedules `MissedDeploymentWorker`
- Worker pulls updates and deploys automatically

### 3. API Endpoints (For Automation)

```bash
# GitHub webhook (from GitHub Actions)
POST /api/v1/deploy/webhook
# Validates GitHub signature
# Only accepts main branch pushes

# Internal deployment (from Home Assistant)
POST /api/v1/deploy/internal
# Only accepts requests from HA IP

# Manual deployment (with API key)
POST /api/v1/deploy/manual
Header: X-API-KEY: your-key

# Check deployment status
GET /api/v1/deploy/status
```

## 🔧 Configuration Files

### Rake Tasks
- `lib/tasks/hass_deploy.rake` - Home Assistant VM deployment
- `lib/tasks/host_deploy.rake` - Sinatra host deployment
- `lib/tasks/sync_config.rake` - Original config sync (still works)

### GitHub Actions
- `.github/workflows/deploy.yml` - CI/CD pipeline

### Home Assistant Automations
- `config/homeassistant/automations/deployment.yaml` - Webhook handler
- `config/homeassistant/shell_commands.yaml` - SSH commands to host

## 📋 Deployment Checklist

### Before First Deploy
- [ ] SSH keys configured (`rake hass:setup_ssh`)
- [ ] `.env.deployment` configured with correct IPs
- [ ] GitHub secrets configured (if using webhooks)
- [ ] Home Assistant webhook URL configured

### Each Deploy
- [ ] Tests passing locally
- [ ] VCR cassettes committed (for CI)
- [ ] No uncommitted changes
- [ ] Check what will deploy: `rake deploy:check`

## 🚨 Troubleshooting

### Common Issues

**"startup deployment check failed missing endpoint"**
- Fixed in latest version - was calling wrong method signature
- Pull latest code to resolve

**SSH connection failed**
```bash
# Check connectivity
rake hass:status

# Verify SSH key
ssh homeassistant@192.168.1.100 'exit'

# Setup SSH if needed
rake hass:setup_ssh
```

**Deployment not triggering**
```bash
# Check git status
rake deploy:check

# Manual trigger
rake deploy:full

# Check logs
rake host:logs
```

**Tests failing in CI**
- Ensure all tests use VCR cassettes
- No external API calls allowed in CI
- Record cassettes locally first

## 🔄 Rollback

If deployment causes issues:

```bash
# On production Mac Mini
cd /path/to/glitchcube
git log --oneline -5  # Find good commit
git reset --hard <commit-hash>
bundle exec rake host:restart

# Restore HA config from backup
ssh homeassistant@vm-ip 'ls /config/backups'
# Pick a backup and restore manually
```

## 📊 Monitoring Deployment

```bash
# Check deployment status
rake status  # Shows both host and HA status

# View deployment logs
tail -f log/sinatra.log
tail -f log/proposed_fixes/*  # Self-healing logs

# Check Home Assistant logs
ssh homeassistant@vm-ip 'tail -f /config/home-assistant.log'
```

## 🔐 Security Notes

- GitHub webhook validates signatures
- Internal endpoints only accept local IPs
- API key required for manual deployment
- No API keys in GitHub Actions (uses webhooks)
- All tests in CI use VCR cassettes (no external calls)

## 📝 Environment Variables

### Required for Deployment
```bash
# .env.deployment
HASS_VM_HOST=192.168.1.100
HASS_VM_USER=homeassistant

# .env (for manual API deployment)
DEPLOYMENT_API_KEY=your-secret-key
GITHUB_WEBHOOK_SECRET=github-secret
```

### CI Environment (GitHub Actions)
```bash
CI=true
VCR_RECORD_MODE=none
DISABLE_EXTERNAL_REQUESTS=true
```

## 🎯 Quick Reference

```bash
# Most common commands
rake hass:deploy       # Deploy HA config
rake host:deploy       # Deploy Sinatra
rake deploy:full       # Deploy everything
rake deploy:check      # What needs deploying?
rake status           # System status

# During development
rake hass:pull        # Get latest HA config
rake host:dev         # Run Sinatra locally
```