# Easy Nginx Reverse Proxy

## Files
- `default` - Main nginx configuration
- `reverse-proxy.conf` - Shared proxy settings

## Setup
1. Copy `default` to `/etc/nginx/sites-available/`
2. Copy `reverse-proxy.conf` to `/etc/nginx/`
3. Update domain names in `default` (replace `example.com`)
4. Update port mappings in the `$proxy_port` map
5. **Optional Auth**: Create htpasswd files:
   - `/var/www/internal.htpasswd` (for staging/dev)
   - `/var/www/external.htpasswd` (for beta)
   - Remove auth lines from server block if not needed
6. Enable site: `ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/`
7. Test: `nginx -t`
8. Reload: `systemctl reload nginx`

## Creating htpasswd Files
```bash
# Create new file (-c) and add users
htpasswd -c /var/www/internal.htpasswd username1
htpasswd /var/www/internal.htpasswd username2
```
