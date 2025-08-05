# Mac Mini VM Deployment Guide

This guide covers the deployment setup for running Glitch Cube with Home Assistant in a VM and Sinatra on the Mac mini host.

## Enabling Mac Mini Deployment

Set the following in your `.env` file:
```bash
MAC_MINI_DEPLOYMENT=true
```

When `false`, the system will use the traditional Docker/Pi deployment.

## Architecture Overview

```
GitHub → GitHub Actions
           ├─→ Webhook → Home Assistant (VM) → Git Pull → Update Config
           └─→ Webhook → Sinatra (Host) → Git Pull → Restart Service
```

- **No shared folders** - Each system pulls from GitHub independently
- **No SSH between host and VM** - Clean separation of concerns
- **Independent deployments** - Each system can update without affecting the other

## Initial Setup

### 1. Home Assistant VM Setup

Inside the VM, run the setup script:

```bash
# Clone the repository first
cd /home/homeassistant
git clone https://github.com/YOUR_ORG/glitchcube.git glitchcube_repo

# Run the setup script
bash glitchcube_repo/scripts/setup-vm-deployment.sh
```

Add to your Home Assistant `configuration.yaml`:

```yaml
# Shell command for git updates
shell_command:
  update_from_git: '/usr/local/bin/update_ha_config.sh'

# Input helpers for tracking deployment
input_boolean:
  glitchcube_deploying:
    name: Glitch Cube Deploying
    initial: off

input_text:
  last_deployment_time:
    name: Last Deployment Time
    initial: "never"
```

Copy the new automation to your automations directory:
```bash
cp /home/homeassistant/glitchcube_repo/config/homeassistant/automations/vm_git_deploy.yaml /config/automations/
```

### 2. Sinatra Host Setup

On the Mac mini host:

1. Ensure the Glitch Cube app is cloned and running
2. Set the webhook secret in your environment:
   ```bash
   export GITHUB_WEBHOOK_SECRET="your-secret-here"
   ```
3. The `/deploy` endpoint is automatically available when the app runs

### 3. GitHub Repository Setup

1. Go to your repository Settings → Secrets and variables → Actions
2. Add these secrets:
   - `HA_WEBHOOK_URL`: Your Home Assistant webhook URL (e.g., `https://xxx.ui.nabu.casa/api/webhook/github_deploy_trigger`)
   - `SINATRA_DEPLOY_URL`: Your Sinatra deployment URL (e.g., `https://yourapp.com/deploy`)
   - `GITHUB_WEBHOOK_SECRET`: A random secret for webhook verification

3. Enable the new workflow:
   - The `deploy-mac-mini.yml` workflow will trigger on pushes to main
   - You can also trigger it manually from Actions tab

## Deployment Flow

### Automatic Deployment

1. Push code to the `main` branch
2. GitHub Actions workflow triggers
3. Workflow sends webhooks to both HA and Sinatra
4. Each system independently:
   - Pulls from GitHub
   - Updates its files
   - Restarts if needed

### Manual Deployment

#### Home Assistant (VM)
```bash
# SSH into VM
cd /home/homeassistant/glitchcube_repo
/usr/local/bin/update_ha_config.sh
```

#### Sinatra (Host)
```bash
cd /path/to/glitchcube
git pull origin main
bundle install  # if Gemfile changed
# Restart service (depends on your setup)
launchctl unload ~/Library/LaunchAgents/com.glitchcube.plist
launchctl load ~/Library/LaunchAgents/com.glitchcube.plist
```

## What Gets Deployed

### Home Assistant VM
- Only files from `config/homeassistant/*` are copied to `/config/`
- Custom components from `homeassistant_components/*` to `/config/custom_components/`
- The VM ignores all other files (Ruby app, docs, etc.)

### Sinatra Host
- Entire repository is updated
- Gems are installed if `Gemfile` changed
- Service is restarted

## Monitoring Deployments

### Home Assistant
- Check notifications in the UI
- View logs: `tail -f /var/log/ha_config_updater.log`
- Check deployment status in Developer Tools → States → `input_text.last_deployment_time`

### Sinatra
- Check application logs
- Monitor service status

## Rollback

### Home Assistant
The VM deployment script creates backups before updating:
```bash
# Backups are stored in /config/backups/
ls -la /config/backups/
# Restore a backup
cp -r /config/backups/20240108-120000/* /config/
```

### Sinatra
Use git to rollback:
```bash
cd /path/to/glitchcube
git log --oneline -10  # Find the commit to rollback to
git reset --hard <commit-hash>
# Restart service
```

## Troubleshooting

### Webhook Not Triggering
1. Verify webhook URLs are correct in GitHub secrets
2. Check if HA webhook is accessible: `curl -X POST <webhook-url>`
3. Look for errors in GitHub Actions logs

### Deployment Failing
1. **VM**: Check `/var/log/ha_config_updater.log`
2. **Host**: Check Sinatra application logs
3. Ensure git credentials are set up (for private repos)

### Service Not Restarting
1. **HA**: May need to manually restart from UI
2. **Sinatra**: Check if launchd plist exists and is loaded

## Security Notes

- Webhook endpoints should use HTTPS
- GitHub webhook secret prevents unauthorized deployments
- Each system only has access to what it needs
- No SSH keys between host and VM reduces attack surface