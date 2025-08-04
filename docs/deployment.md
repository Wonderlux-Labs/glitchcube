# Glitch Cube Deployment

## Automatic Deployment Flow

1. **Push to GitHub** → Triggers GitHub Action
2. **GitHub Action** → Sends webhook to Home Assistant (via Nabu Casa)
3. **Home Assistant** → Receives webhook and triggers automation
4. **Automation** → Runs `auto-deploy.sh` script
5. **Script** → Pulls code, updates containers, restarts services

## Manual Deployment Options

### From your machine:
```bash
# Traditional deploy
./scripts/deploy.sh "commit message"

# Or use rake
bundle exec rake deploy:push["commit message"]
bundle exec rake deploy:quick
```

### From Home Assistant UI:
1. Go to Developer Tools → Services
2. Service: `shell_command.deploy_glitchcube`
3. Click "Call Service"

### Rollback:
```bash
# From device
bundle exec rake deploy:rollback

# From Home Assistant
# Service: shell_command.rollback_glitchcube
```

## Monitoring Deployment

### Home Assistant Sensors:
- `sensor.glitchcube_deployment_status` - Shows if update available
- `sensor.glitchcube_current_commit` - Current deployed commit
- `sensor.glitchcube_remote_commit` - Latest GitHub commit
- `input_boolean.glitchcube_deploying` - Deployment in progress

### Logs:
```bash
# On device
tail -f /var/log/glitchcube-auto-deploy.log

# Home Assistant logs
# Settings → System → Logs
```

## Webhook URL

The deployment webhook is publicly accessible at:
```
https://zjd6lgd6yhigawnj06mkguhholcsfdul.ui.nabu.casa:8123/api/webhook/github_deploy_glitchcube
```

No authentication required for webhooks - Home Assistant handles security through the unique webhook ID.