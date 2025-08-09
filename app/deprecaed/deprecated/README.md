# GitHub Actions Setup

## Deployment Workflows

Glitch Cube supports multiple deployment workflows:

1. **`deploy-conditional.yml`** - Automatically detects deployment type based on MAC_MINI_DEPLOYMENT setting
2. **`deploy-mac-mini.yml`** - Mac mini VM deployment (webhooks to HA and Sinatra)
3. **`deploy.yml`** - Traditional Docker/Pi deployment (SSH based)

The conditional workflow will automatically choose the right deployment method.

## Auto-Deploy Workflow

The appropriate workflow automatically deploys to your Glitch Cube whenever you push to the `main` branch.

### Required GitHub Secrets

1. Go to your repository Settings → Secrets and variables → Actions
2. Add the following secrets:

#### For Mac mini VM Deployment:
- `HA_WEBHOOK_URL`: Your Home Assistant webhook URL (e.g., `https://xxx.ui.nabu.casa/api/webhook/github_deploy_trigger`)
- `SINATRA_DEPLOY_URL`: Your Sinatra deployment URL (e.g., `https://yourapp.com/deploy`)
- `GITHUB_WEBHOOK_SECRET`: A random secret for webhook verification (optional but recommended)

#### For Docker/Pi Deployment:

- `DEPLOY_HOST`: The hostname or IP of your Glitch Cube (e.g., `glitchcube.local` or `192.168.1.100`)
- `DEPLOY_USER`: The SSH username (e.g., `eric`)
- `DEPLOY_KEY`: The private SSH key for deployment

### Setting up SSH Key

1. On your local machine, generate a deployment key pair:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/glitchcube_deploy -C "github-actions"
```

2. Add the public key to your Glitch Cube:
```bash
ssh-copy-id -i ~/.ssh/glitchcube_deploy.pub eric@glitchcube.local
```

3. Copy the private key content:
```bash
cat ~/.ssh/glitchcube_deploy
```

4. Paste the entire private key (including the BEGIN/END lines) into the `DEPLOY_KEY` secret on GitHub

### Manual Deployment

You can also trigger deployment manually:
1. Go to Actions tab
2. Select "Deploy to Glitch Cube"
3. Click "Run workflow"

### Deployment Process

The workflow:
1. Pulls latest code on the device
2. Updates Home Assistant configuration files
3. Installs custom components
4. Restarts necessary services
5. Reports success/failure

### Troubleshooting

- Check the Actions tab for deployment logs
- Ensure your Glitch Cube is accessible from the internet (or use a self-hosted runner)
- Verify SSH key permissions are correct
- Check that the deploy user has sudo access (for component installation)