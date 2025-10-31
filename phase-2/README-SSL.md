# GitLab with Traefik SSL Reverse Proxy

This setup provides a complete GitLab CI/CD environment behind a Traefik reverse proxy with SSL/TLS encryption using self-signed certificates.

## Architecture

```
Internet/Browser (HTTPS:443)
         ↓
    Traefik Reverse Proxy
    - SSL Termination
    - HTTP → HTTPS redirect
         ↓
      GitLab (HTTP:80 internal)
         ↓
    GitLab Runners (Docker & Shell)
```

## Components

1. **Traefik v3.2** - Reverse proxy with SSL termination
   - Ports: 80 (HTTP), 443 (HTTPS), 8080 (Dashboard)
   - Auto HTTP → HTTPS redirect
   - Self-signed certificate for gitlab.local

2. **GitLab CE 18.3.5** - Main GitLab instance
   - External URL: https://gitlab.local
   - Internal: HTTP only (Traefik handles SSL)
   - SSH: Port 2222
   - Resources: 16GB RAM, 6 CPUs

3. **GitLab Runners** - CI/CD executors
   - gitlab-runner-docker: Docker executor (2GB RAM, 3 CPUs)
   - gitlab-runner-shell: Shell executor (8GB RAM, 5 CPUs, KVM support)

## Quick Start

### 1. Prerequisites

Ensure you have:
- Docker & Docker Compose installed
- `.env` file configured (for SMTP settings)
- Sufficient system resources (24GB+ RAM recommended)

### 2. Add GitLab hostname to /etc/hosts

```bash
echo "127.0.0.1 gitlab.local" | sudo tee -a /etc/hosts
```

### 3. Run the setup script

```bash
./setup-with-ssl.sh
```

This script will:
1. Generate self-signed SSL certificates (if not present)
2. Start Traefik, GitLab, and runners in the correct order
3. Wait for health checks to pass
4. Display access URLs

### 4. Access GitLab

- **GitLab Web**: https://gitlab.local
- **Traefik Dashboard**: http://localhost:8080

⚠️ Your browser will warn about the self-signed certificate. This is expected - click "Advanced" and proceed.

## Manual Operations

### Generate SSL Certificates Only

```bash
./generate-ssl-cert.sh
```

Certificates will be created in `./certs/`:
- `gitlab.local.crt` - Certificate
- `gitlab.local.key` - Private key
- `gitlab.local.csr` - Certificate signing request

Certificate details:
- **CN**: gitlab.local
- **SAN**: gitlab.local, *.gitlab.local
- **Validity**: 365 days
- **Key Size**: 2048-bit RSA

### Start Services

```bash
./start.sh
```

Startup order:
1. Traefik (waits for health check)
2. GitLab (waits for health check)
3. GitLab Runners

### Stop Services

```bash
./stop.sh
```

Shutdown order:
1. GitLab Runners
2. GitLab
3. Traefik

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f traefik
docker compose logs -f gitlab
docker compose logs -f gitlab-runner-docker
```

### Check Service Status

```bash
docker compose ps
```

## Configuration Files

### docker-compose_gitlab.yml

Main compose file with all services:
- Traefik configuration with SSL mounts
- GitLab with Traefik labels for routing
- Runner configurations

### traefik-dynamic.yml

Traefik dynamic configuration for SSL certificates:
- Certificate paths
- Default certificate store

### SSL Certificate Location

```
./certs/
├── gitlab.local.crt  # Public certificate
├── gitlab.local.key  # Private key
└── gitlab.local.csr  # Certificate signing request
```

## Traefik Configuration Details

### Entry Points

- **web** (port 80): HTTP - automatically redirects to HTTPS
- **websecure** (port 443): HTTPS with SSL/TLS

### GitLab Routing

Traefik labels on GitLab container:
- Routes `gitlab.local` to GitLab service
- Enables TLS on websecure entrypoint
- Load balances to port 80 (internal)

### Dashboard

Access Traefik dashboard at: http://localhost:8080

Shows:
- Active routers and services
- Health checks
- TLS certificates
- Real-time metrics

## GitLab Configuration Changes

The following GitLab settings have been modified for Traefik:

```ruby
external_url 'https://gitlab.local'
nginx['listen_port'] = 80
nginx['listen_https'] = false
nginx['proxy_set_headers'] = {
  "X-Forwarded-Proto" => "https",
  "X-Forwarded-Ssl" => "on"
}
```

This ensures:
- GitLab knows its external URL is HTTPS
- Internal nginx only listens on HTTP (Traefik handles SSL)
- Proper headers are set for redirect and asset URLs

## Troubleshooting

### Certificate Issues

**Problem**: Browser shows certificate error
**Solution**: This is expected for self-signed certs. Click "Advanced" → "Proceed to gitlab.local"

**Problem**: Certificate not loading
**Solution**: Check certificate files exist and have correct permissions:
```bash
ls -la ./certs/
# Should show:
# -rw------- gitlab.local.key (600)
# -rw-r--r-- gitlab.local.crt (644)
```

### Connection Issues

**Problem**: Cannot reach gitlab.local
**Solution**: Ensure /etc/hosts has the entry:
```bash
cat /etc/hosts | grep gitlab.local
# Should show: 127.0.0.1 gitlab.local
```

**Problem**: Traefik not forwarding requests
**Solution**: Check Traefik logs:
```bash
docker compose logs traefik | grep -i error
```

### Port Conflicts

**Problem**: Port 80 or 443 already in use
**Solution**: Stop conflicting services:
```bash
sudo lsof -i :80
sudo lsof -i :443
# Kill the process or modify docker-compose port mappings
```

### Health Check Failures

**Problem**: Services not passing health checks
**Solution**:
1. Check service logs for errors
2. Increase health check timeouts in docker-compose.yml
3. Manually test health endpoints:
```bash
docker exec traefik traefik healthcheck --ping
docker exec gitlab curl -f http://localhost:80/-/health
```

## Upgrading from HTTP to HTTPS

If you're upgrading from a previous HTTP-only setup:

1. **Backup your data**:
```bash
docker compose exec gitlab gitlab-backup create
```

2. **Stop existing services**:
```bash
./stop.sh
```

3. **Generate certificates**:
```bash
./generate-ssl-cert.sh
```

4. **Update compose file** (already done in docker-compose_gitlab.yml)

5. **Start with new configuration**:
```bash
./start.sh
```

6. **Update GitLab external URL** if needed:
   - The external_url is now `https://gitlab.local`
   - GitLab will reconfigure automatically on start

## Production Considerations

For production use, consider:

1. **Real SSL Certificate**: Use Let's Encrypt or a commercial CA instead of self-signed
   - Traefik has built-in Let's Encrypt support
   - Update traefik-dynamic.yml with cert resolver configuration

2. **Security Hardening**:
   - Disable Traefik dashboard in production (remove `--api.insecure=true`)
   - Use secrets management for sensitive data
   - Enable HSTS headers
   - Implement rate limiting

3. **Monitoring**:
   - Enable Prometheus metrics on Traefik
   - Set up log aggregation
   - Configure alerts for health check failures

4. **Backup**:
   - Regular GitLab backups (already configured: 7-day retention)
   - Backup certificates and configuration files
   - Test restoration procedures

## Resources

- Traefik Documentation: https://doc.traefik.io/traefik/
- GitLab Documentation: https://docs.gitlab.com/
- GitLab Runner: https://docs.gitlab.com/runner/

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `generate-ssl-cert.sh` | Generate self-signed SSL certificate |
| `setup-with-ssl.sh` | Complete setup (cert + start services) |
| `start.sh` | Start all services with health checks |
| `stop.sh` | Stop all services gracefully |
| `3.bootup-gitlab_container.sh` | Legacy bootup script (deprecated) |

## Files Overview

| File | Purpose |
|------|---------|
| `docker-compose_gitlab.yml` | Main compose configuration |
| `traefik-dynamic.yml` | Traefik SSL certificate config |
| `.env` | Environment variables (SMTP, etc.) |
| `certs/` | SSL certificate directory |
| `runner-config/` | Docker runner configuration |
| `runner-shell-config/` | Shell runner configuration |
