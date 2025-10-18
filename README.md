# DevOps Server Setup

## Prerequisites

- Ubuntu/Debian server with root access
- Wildcard SSL certificates in `/etc/ssl/private/`:
  - `fullchain.pem`
  - `key.pem`

## Quick Setup

1. **Run the init script**:
   ```bash
   sudo ./server-init.sh
   ```

3. **Update domain names** in `/etc/nginx/sites-available/default` (replace `example.com`)

4. **Add SSH key to GitHub**:
   - Copy `/opt/.ssh/id_ed25519` content
   - Add as `SSH_PRIVATE_KEY` secret in your repository

## What it sets up

- Docker + nginx + cAdvisor
- Deployer user with SSH keys
- Nginx reverse proxy configuration
- Container monitoring

## Usage

Deploy with your existing deployer-action - everything is ready to go!
