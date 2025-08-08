# GitHub → Home Assistant → Sinatra Deployment Setup

This document explains how to set up automated deployment from GitHub to your Raspberry Pi using Home Assistant as a webhook receiver.

## Overview

When you push to the `main` branch, GitHub will automatically:
1. Send webhook to Home Assistant (which has external access)
2. Home Assistant triggers local Sinatra deployment endpoint 
3. Sinatra pulls latest code with `git pull origin main`
4. Syncs Home Assistant configuration with `rake config:push`
5. Restarts Home Assistant and Glitch Cube services

## Setup Steps

### 1. Configure Home Assistant Input Helpers

In Home Assistant, add these input helpers (or set via configuration files):

```yaml
# input_text_deployment.yaml
input_text:
  glitchcube_host_url:
    name: "Glitch Cube Host URL"
    initial: "http://glitchcube:4567"  # Adjust for your setup
```

### 2. Set up GitHub Repository Secret

Go to your GitHub repository → Settings → Secrets and variables → Actions → New repository secret

Add this secret:

#### `HOME_ASSISTANT_WEBHOOK_URL`
- **Value**: Your Home Assistant's external webhook URL with webhook ID
- **Format**: `https://your-ha-domain.com/api/webhook/github_deploy`
- **Note**: The webhook ID `github_deploy` matches the automation trigger
- **Purpose**: Where GitHub sends the deployment webhook

### 3. Test the Setup

#### Manual Test via Home Assistant
```bash
# Test Home Assistant webhook
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"test": "manual deployment"}' \
  https://your-ha-domain.com/api/webhook/github_deploy
```

#### Check Deployment Status
```bash
curl -s http://your-pi-ip:4567/api/v1/deploy/status | jq .
```

#### Trigger GitHub Action
- Go to your repository → Actions → "Deploy via Home Assistant" → Run workflow
- Or simply push a commit to the `main` branch

#### Manual Deployment via Home Assistant UI
- Go to Developer Tools → Services
- Call service: `script.manual_glitchcube_deployment`
- Set data: `{"message": "Manual test", "committer": "Your Name"}`

## Security Considerations

### Art Installation Context
- This is designed for a single-user autonomous art installation
- Typically deployed in controlled environments (like Burning Man desert)
- No security concerns for external attackers - it's a cube in the desert!

### Authentication
- **GitHub → Home Assistant**: No authentication needed 
- **Home Assistant → Sinatra**: IP-based filtering (only accepts local network requests)
- Worst case scenario: someone triggers an extra deployment (no harm done)
- Simple and appropriate for art installation context

## Troubleshooting

### Check Application Logs
```bash
# On Raspberry Pi
docker-compose logs -f glitchcube

# Or if running directly
tail -f logs/application.log
```

### Check GitHub Actions
- Go to your repository → Actions
- Click on the latest workflow run
- Check for any errors in the webhook step

### Test Connectivity
```bash
# From anywhere, test if your Pi is reachable
curl -s http://your-pi-ip:4567/health

# Check if webhook endpoint exists
curl -X POST http://your-pi-ip:4567/api/v1/deploy/webhook
# Should return 401 (missing signature) - that's expected
```

### Common Issues

1. **401 Unauthorized**: Check that secrets match between GitHub and Pi
2. **Connection refused**: Check firewall/network configuration  
3. **500 Internal Server Error**: Check Pi logs, may be git/ssh issues
4. **Git pull fails**: Ensure Pi has SSH keys for GitHub access

## Monitoring

### Check Deployment Status
The `/api/v1/deploy/status` endpoint provides:
- Current git branch and commit
- Number of commits behind remote
- Home Assistant status
- Last check timestamp

### Logs
All deployment activities are logged via `Services::LoggerService` with:
- Webhook requests (GitHub payload info)
- Deployment step results (git pull, config sync, restarts)
- Error details for failed deployments

## Manual Deployment

If needed, you can trigger deployment without GitHub:

```bash
# Using the API
curl -X POST \
  -H "X-API-Key: your-api-key" \
  -d '{"message": "Emergency deploy", "branch": "main"}' \
  http://your-pi-ip:4567/api/v1/deploy/manual

# Using rake task directly on Pi
rake deploy:pull
```

## File Structure

```
.github/workflows/deploy-on-push.yml  # GitHub Actions workflow
lib/routes/api/deployment.rb          # Webhook endpoint code
docs/github-webhook-setup.md          # This documentation
```

The webhook system integrates with your existing rake tasks:
- `rake config:push` - Sync HA configuration
- SSH commands for Home Assistant restart
- Docker/systemd service restart detection