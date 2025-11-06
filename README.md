# Self-Hosting CI/CD Pipeline for Flutter Applications with GitLab

A complete self-hosted CI/CD solution for Flutter mobile application development using GitLab CE, GitLab Runners, and Docker containers. This setup provides a production-ready environment with SSL support, automated builds, testing, and deployment capabilities.

## Overview

This repository provides a step-by-step guide to set up a self-hosted CI/CD pipeline for Flutter development with the following components:

- **GitLab CE 18.3.5** - Source control and CI/CD orchestration
- **Traefik v3.2** - Reverse proxy with SSL/TLS termination
- **GitLab Runners** - Docker and Shell executors for build jobs
- **Flutter Docker Image** - Pre-configured Flutter environment
- **Android Emulator Support** - KVM-based emulator for integration testing

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Developer Workstation                    │
│                  (Push code to GitLab)                      │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Traefik Reverse Proxy                    │
│              (HTTPS:443 → HTTP:80 internal)                 │
│              SSL Termination & Routing                      │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      GitLab CE Server                       │
│                   (https://gitlab.local)                    │
│              - Source Code Management                       │
│              - CI/CD Pipeline Orchestration                 │
│              - Web Interface & API                          │
└────────────────┬───────────────────────┬────────────────────┘
                 │                       │
        ┌────────▼─────────┐     ┌───────▼─────────┐
        │  GitLab Runner   │     │  GitLab Runner  │
        │ (Docker Executor)│     │ (Shell Executor)│
        │                  │     │  + KVM Support  │
        │ - Build APKs     │     │ - Integration   │
        │ - Run Tests      │     │   Tests         │
        │ - Deploy         │     │ - Emulator      │
        └──────────────────┘     └─────────────────┘
```

## Prerequisites

### Hardware Requirements

- **CPU**: 8+ cores (recommended for parallel builds and emulator)
- **RAM**: 24GB+ (GitLab: 16GB, Docker Runner: 2GB, Shell Runner: 8GB)
- **Storage**: 100GB+ SSD (for Docker images, builds, and caches)
- **Virtualization**: KVM support for Android emulator

### Software Requirements

- Linux server (Debian 12+ recommended)
- Docker Engine 20.10+
- Docker Compose v2
- Internet connection for initial setup
- In Linux server, create the 1st user named gitlab-runner with id 1000 (for matching to user ubuntu in flutter image) and sudo previliege.

## Installation Guide

NOTE: execute the following steps as the user gitlab-runner 

### Phase 1: Host Preparation

Prepare your host system with all required dependencies.

#### Step 1.1: Install System Dependencies

```bash
cd phase-1

# Run the host preparation script
bash 1.prepare-host.sh
```

This script will:
- Update system packages
- Install Docker and Docker Compose
- Install KVM and virtualization tools
- Install Android development tools (OpenJDK, ADB)
- Add the gitlab-runner user to docker, kvm, and libvirt groups

**Important**: After running this script, log out and log back in for group changes to take effect.

Verify KVM support:
```bash
sudo kvm-ok
# Expected output: "KVM acceleration can be used"
```

#### Step 1.2: Create Directory Structure

```bash
# Set up the working directory structure
bash 2.setup-dir.sh
```

This creates the directory hierarchy for GitLab data, Flutter builds, and cache storage.

**Note**: The script expects a `.sh-env` file in the parent directory that defines `$WORKFLOW_HOME`. If not present, manually create the directories:

```bash
export WORKFLOW_HOME=$HOME/ci-cd-workspace
mkdir -p $WORKFLOW_HOME/ci-cd/{gitlab,flutter,jenkins,monitoring}
```

### Phase 2: GitLab and Runner Setup

Set up GitLab CE server with Traefik reverse proxy and GitLab runners.

#### Step 2.1: Configure Environment Variables

Create a `.env` file in the `phase-2` directory with your SMTP settings:

```bash
cd ../phase-2

cat > .env <<EOF
# SMTP Configuration (optional, for GitLab email notifications)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_DOMAIN=gmail.com
GITLAB_EMAIL_FROM=gitlab@yourdomain.com
EOF
```

#### Step 2.2: Add GitLab Hostname to /etc/hosts

**For local access** (on the GitLab host):
```bash
echo "127.0.0.1 gitlab.local" | sudo tee -a /etc/hosts
```

**For remote access** (from other machines on your network):
```bash
# On remote machines, replace <GITLAB_SERVER_IP> with the actual IP
echo "<GITLAB_SERVER_IP> gitlab.local" | sudo tee -a /etc/hosts
```

**Note**: The GitLab container listens on `0.0.0.0:443`, so it's accessible from other machines on your network.

#### Step 2.3: Generate SSL Certificates and Start Services

```bash
# One-command setup: generates SSL certs and starts all services
bash setup-with-ssl.sh
```

This will:
1. Generate self-signed SSL certificates (valid for 365 days)
2. Start Traefik reverse proxy
3. Start GitLab CE server
4. Start GitLab runners (Docker and Shell executors)
5. Wait for health checks to pass

**Alternative**: Manual step-by-step approach:

```bash
# Generate SSL certificates only
bash generate-ssl-cert.sh

# Start services
bash start.sh

# View logs
docker compose -f docker-compose_gitlab.yml logs -f

# Stop services
bash stop.sh
```

#### Step 2.4: Install Self-Signed SSL Certificate (Optional)

To avoid browser security warnings, install the self-signed certificate to your system's trust store.

**On Debian/Ubuntu**:
```bash
# Copy certificate to system trust store
sudo cp phase-2/certs/gitlab.local.crt /usr/local/share/ca-certificates/gitlab.local.crt

# Update CA certificates
sudo update-ca-certificates

# Verify installation
sudo update-ca-certificates --verbose | grep gitlab.local
```

**On the GitLab host** (to avoid HTTPS warnings for curl commands):
```bash
sudo cp phase-2/certs/gitlab.local.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

**For browsers on remote machines**:
1. Copy `phase-2/certs/gitlab.local.crt` to the remote machine
2. Import it into your browser's certificate manager:
   - **Firefox**: Preferences → Privacy & Security → Certificates → View Certificates → Authorities → Import
   - **Chrome**: Settings → Privacy and security → Security → Manage certificates → Authorities → Import

#### Step 2.5: Access GitLab Web Interface

Open your browser and navigate to: **https://gitlab.local**

**Note**: If you didn't install the SSL certificate, your browser will show a security warning. Click "Advanced" and proceed to the site.

#### Step 2.6: Set Root Password

Wait for GitLab to fully initialize (this may take 3-5 minutes). Then set the root password:

```bash
# Set a secure password (minimum 8 characters)
bash 3.set-root-pwd.sh "YourSecurePassword123!"
```

#### Step 2.7: Create Additional GitLab Users (Optional)

```bash
# Interactive mode (recommended - password is hidden)
bash 5.create-gitlab-user.sh

# Or with command-line arguments
bash 5.create-gitlab-user.sh -u developer -e dev@example.com -a

# Create admin user
bash 5.create-gitlab-user.sh -u admin -e admin@example.com -a --skip-confirmation
```

### Phase 3: GitLab Runner Installation (Non-Containerized)

Install and configure GitLab Runner as a system service. This is the **recommended approach** for production use, as it provides better performance and easier access to system resources like KVM for Android emulator.

**Note**: While the Docker Compose setup includes containerized runners, the primary runner used in this setup is a non-containerized GitLab Runner installed as a system service under the `gitlab-runner` user.

#### Step 3.1: Install GitLab Runner Binary

```bash
cd ../phase-3

# Download and install GitLab Runner
curl -L --output /tmp/gitlab-runner "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"

# Install to system
sudo mv /tmp/gitlab-runner /usr/local/bin/gitlab-runner
sudo chmod +x /usr/local/bin/gitlab-runner

# Verify installation
gitlab-runner --version
```

#### Step 3.2: Create GitLab Runner User and Setup Directories

```bash
# Create gitlab-runner user if not exists
sudo useradd --system --shell /bin/bash --home /home/gitlab-runner --create-home gitlab-runner

# Add gitlab-runner user to necessary groups
sudo usermod -aG docker gitlab-runner
sudo usermod -aG kvm gitlab-runner
sudo usermod -aG libvirt gitlab-runner

# Create working directories
sudo mkdir -p /home/gitlab-runner/ci-cd/working/{builds,cache}
sudo mkdir -p /home/gitlab-runner/.gitlab-runner

# Set ownership
sudo chown -R gitlab-runner:gitlab-runner /home/gitlab-runner

# Fix .bash_logout to prevent errors
# Remove the "clear" command that causes issues in non-interactive shells
sudo sed -i '/^clear/d' /home/gitlab-runner/.bash_logout 2>/dev/null || true
```

**Important**: The `.bash_logout` cleanup prevents errors when GitLab Runner executes jobs in non-interactive shell mode.

#### Step 3.3: Install GitLab Runner as a Service

```bash
# Install and start the service
bash 1.install-gitlab-runner-svc.sh

# Verify service status
sudo systemctl status gitlab-runner

# Enable service to start on boot
sudo systemctl enable gitlab-runner
```

This script installs GitLab Runner as a systemd service that:
- Runs as the `gitlab-runner` user
- Uses config file: `/home/gitlab-runner/.gitlab-runner/config.toml`
- Uses working directory: `/home/gitlab-runner/ci-cd/working`

#### Step 3.4: Understand Runner Configuration

The GitLab Runner will use the **shell executor**, which:
- Runs jobs directly on the host (not in containers)
- Has full access to system resources (Docker, KVM, Android SDK)
- Best for: All job types including builds, tests, and integration tests with Android emulator
- More performant than Docker executor for heavy workloads

#### Step 3.5: Get Runner Authentication Token

You need a runner authentication token from GitLab to register runners.

**Option A**: Via GitLab UI (Recommended)
1. Log in to GitLab as root/admin
2. Go to **Admin Area** → **CI/CD** → **Runners**
3. Click **New instance runner**
4. Select **Linux** as the platform
5. Add tags if desired (e.g., `shell`, `linux`, `android`)
6. Check "Run untagged jobs" if you want this runner to pick up all jobs
7. Click **Create runner**
8. Copy the authentication token (starts with `glrt-`)

**Option B**: Via Script (GitLab API)

First, create a personal access token in GitLab:
1. Go to **User Settings** → **Access Tokens**
2. Create token with scopes: `api`, `create_runner`
3. Copy the token (starts with `glpat-`)

Then run:
```bash
# Set environment variables
export GITLAB_URL=https://gitlab.local
export GITLAB_TOKEN=glpat-your-token-here

# Create runner and get authentication token
bash 3.create-gitlab-instance-runner.sh \
  -d "shell-runner-main" \
  -g "shell,linux,android" \
  -o /tmp/runner_token.txt

# The authentication token will be saved to /tmp/runner_token.txt
cat /tmp/runner_token.txt
```

#### Step 3.6: Register the GitLab Runner

Register the runner with GitLab using the authentication token:

```bash
# Replace with your actual token from previous step
export RUNNER_TOKEN="glrt-your-token-here"

# Register shell executor runner
sudo gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.local" \
  --token "$RUNNER_TOKEN" \
  --executor "shell" \
  --description "shell-runner-main" \
  --tag-list "shell,linux,android" \
  --run-untagged="true" \
  --builds-dir "/home/gitlab-runner/ci-cd/working/builds" \
  --cache-dir "/home/gitlab-runner/ci-cd/working/cache"

# Restart the runner service
sudo systemctl restart gitlab-runner

# View runner status
sudo gitlab-runner list
```

**Alternative**: Use the provided script for more options:

```bash
# Interactive registration
bash 5.register-gitlab-runner.sh

# Or with command-line arguments
bash 5.register-gitlab-runner.sh \
  -t "$RUNNER_TOKEN" \
  -u https://gitlab.local \
  -n 'shell-runner-main' \
  -e shell \
  --deploy-method local
```

#### Step 3.7: Verify Runner Status

Check that the runner is connected and active:

**Via GitLab UI**:
1. Go to **Admin Area** → **CI/CD** → **Runners**
2. You should see your runner listed with a green status indicator
3. Click on the runner to view details and recent jobs

**Via CLI**:
```bash
# List registered runners
sudo gitlab-runner list

# Check service status
sudo systemctl status gitlab-runner

# View runner logs
sudo journalctl -u gitlab-runner -f
```

#### Step 3.8: Configure Runner Concurrency (Optional)

Adjust the number of concurrent jobs the runner can handle:

```bash
# Edit the config file
sudo nano /home/gitlab-runner/.gitlab-runner/config.toml

# Update the concurrent value (default is 1)
# concurrent = 4  # Allow 4 jobs to run simultaneously

# Restart the service
sudo systemctl restart gitlab-runner
```

### Phase 4: GitLab CI/CD Pipeline Integration

(Phase 4 is focused on integration and testing - not yet documented in phase-4 subdirectory)

### Phase 5: Build Flutter Docker Image

Create a custom Flutter Docker image for your CI/CD pipeline.

#### Step 5.1: Review Flutter Version

```bash
cd ../phase-5

cat flutter.version
# Example: FLUTTER_VERSION=3.22.0
```

Update `flutter.version` if you need a different Flutter version.

#### Step 5.2: Build Flutter Docker Image

```bash
# Build the Flutter image
bash build-flutter_img.sh
```

This creates a Docker image with:
- Flutter SDK (version from flutter.version)
- Android SDK platforms (33, 34)
- Android build tools (30.0.3, 33.0.3, 34.0.0)
- Pre-accepted Android licenses
- Tsinghua mirror configuration (for faster downloads in China)

#### Step 5.3: Tag Image for CI/CD

```bash
# Tag the image for use in GitLab CI
export FLUTTER_VERSION=$(cat flutter.version | grep FLUTTER_VERSION | cut -d= -f2)
docker tag flutter:${FLUTTER_VERSION} flutter-ci:latest
```

## Using the CI/CD Pipeline

### Sample GitLab CI Configuration

A complete `.gitlab-ci.yml` example is provided at the root of this repository. It includes:

**Stages**:
1. **build** - Build Android APKs and AAB files
2. **test** - Static analysis, unit tests, backend tests
3. **integration-test** - Android emulator-based integration tests
4. **deploy** - Deploy to Google Play Store
5. **notify** - Slack notifications for success/failure

**Key Features**:
- Flutter static analysis and formatting checks
- Unit test coverage reports
- Android APK/AAB builds with split-per-ABI
- Integration tests with Android emulator
- iOS build support (requires macOS runner)
- Automated deployment to Play Store
- Slack notifications

### Setting Up Your Flutter Project

1. **Create a new project** in GitLab UI or push an existing project

2. **Add `.gitlab-ci.yml`** to your Flutter project:

```bash
cp .gitlab-ci.yml /path/to/your/flutter/project/
cd /path/to/your/flutter/project
git add .gitlab-ci.yml
git commit -m "Add GitLab CI/CD configuration"
git push origin main
```

3. **Configure CI/CD variables** in GitLab:
   - Go to **Settings** → **CI/CD** → **Variables**
   - Add the following variables:
     - `CI_SLACK_WEBHOOK` - Slack webhook URL for notifications
     - `PLAY_STORE_JSON_KEY` - Base64-encoded Google Play service account JSON key

4. **Customize the pipeline** for your project:
   - Update `FLUTTER_VERSION` to match your project
   - Modify stages and jobs as needed
   - Adjust runner tags based on your runner configuration

### Running Your First Pipeline

1. Push code to GitLab:
```bash
git push origin main
```

2. Monitor the pipeline:
   - Go to **CI/CD** → **Pipelines** in GitLab UI
   - Click on the running pipeline to view job details
   - View logs for each job

3. Download build artifacts:
   - Navigate to **CI/CD** → **Jobs**
   - Click on the `android-build` job
   - Download APK/AAB files from the artifacts section

## Configuration Files Reference

### phase-2/docker-compose_gitlab.yml

Main Docker Compose configuration with:
- Traefik reverse proxy (ports 80, 443, 8080)
- GitLab CE server (16GB RAM, 6 CPUs)
- Optional containerized runners (for reference; the main runner is non-containerized)

**Note**: The production setup uses a non-containerized GitLab Runner installed via phase-3, not the containerized runners in docker-compose.

### phase-2/traefik-dynamic.yml

Traefik dynamic configuration for SSL certificates.

### phase-5/Dockerfile

Flutter Docker image definition based on `ghcr.io/cirruslabs/flutter:3.22.0`.

## Troubleshooting

### GitLab Container Not Starting

**Problem**: GitLab container fails health checks or doesn't start

**Solutions**:
1. Check system resources: `free -h` and `df -h`
2. View GitLab logs: `docker logs gitlab`
3. Increase Docker memory limit in `docker-compose_gitlab.yml`
4. Wait longer (GitLab can take 3-5 minutes to fully initialize)

### Runner Not Connecting

**Problem**: Runner shows as offline in GitLab UI

**Solutions**:
1. Check runner service status:
   ```bash
   sudo systemctl status gitlab-runner
   sudo journalctl -u gitlab-runner -n 50
   ```
2. Verify runner token is correct:
   ```bash
   sudo cat /home/gitlab-runner/.gitlab-runner/config.toml
   ```
3. Check network connectivity:
   ```bash
   sudo -u gitlab-runner curl -I https://gitlab.local
   ```
4. Ensure SSL certificate is installed system-wide:
   ```bash
   sudo update-ca-certificates --verbose | grep gitlab.local
   ```
5. Check gitlab-runner user permissions:
   ```bash
   groups gitlab-runner
   # Should include: docker, kvm, libvirt
   ```
6. Restart the runner service:
   ```bash
   sudo systemctl restart gitlab-runner
   ```

### Android Emulator Fails to Start

**Problem**: Integration tests fail with emulator errors

**Solutions**:
1. Verify KVM is working: `sudo kvm-ok`
2. Check KVM group membership: `groups` (should include 'kvm')
3. Verify group ID in docker-compose matches: `getent group kvm`
4. Ensure `/dev/kvm` is accessible in runner container
5. Check emulator script: Ensure `$HOME/start_emulator.sh` exists

### SSL Certificate Issues

**Problem**: Browser shows certificate errors

**Solution**: This is expected for self-signed certificates. Click "Advanced" → "Proceed to gitlab.local (unsafe)".

**Problem**: Certificate not loading in Traefik

**Solutions**:
1. Check certificate files exist:
   ```bash
   ls -la phase-2/certs/
   ```
2. Verify permissions: Key file should be 600, cert file 644
3. Regenerate certificates:
   ```bash
   cd phase-2
   bash generate-ssl-cert.sh
   ```

### Build Failures

**Problem**: Flutter build job fails

**Solutions**:
1. Verify Flutter Docker image exists: `docker images | grep flutter`
2. Check job logs in GitLab UI for specific errors
3. Ensure `flutter-ci:latest` image is tagged correctly
4. Verify runner has Docker socket access (for Docker executor)
5. Check disk space: `df -h`

## Production Considerations

### Security

1. **Use Real SSL Certificates**:
   - Replace self-signed certificates with Let's Encrypt or commercial CA
   - Traefik has built-in Let's Encrypt support

2. **Secure GitLab**:
   - Use strong passwords (12+ characters)
   - Enable two-factor authentication (2FA)
   - Regularly update GitLab and runners
   - Limit runner token exposure

3. **Network Security**:
   - Use a firewall (ufw, iptables)
   - Restrict SSH access
   - Use VPN for remote access
   - Disable Traefik dashboard in production

### Backup Strategy

1. **GitLab Backups**:
   ```bash
   docker exec gitlab gitlab-backup create
   ```
   Backups are stored in `gitlab_backups` volume (7-day retention)

2. **Configuration Backups**:
   ```bash
   tar -czf gitlab-config-backup.tar.gz \
     phase-2/docker-compose_gitlab.yml \
     phase-2/.env \
     phase-2/certs/ \
     phase-2/runner-config/ \
     phase-2/runner-shell-config/
   ```

3. **Restore from Backup**:
   ```bash
   docker exec gitlab gitlab-backup restore BACKUP=<timestamp>
   ```

### Monitoring

1. **GitLab Metrics**: Prometheus monitoring is enabled in GitLab configuration
2. **Traefik Dashboard**: http://localhost:8080 (disable in production)
3. **Runner Logs**:
   ```bash
   # System service runner logs
   sudo journalctl -u gitlab-runner -f

   # View recent job logs
   sudo tail -f /home/gitlab-runner/ci-cd/working/builds/*/*/.gitlab-ci-trace.log
   ```

### Scaling

1. **Add More Runners**:
   - Register additional runners for different projects
   - Use runner tags to assign jobs to specific runners

2. **Increase Concurrency**:
   - Edit `runner-config/config.toml`
   - Increase `concurrent` value (default: 4)

3. **External Database** (Optional):
   - For high-load scenarios, use external PostgreSQL
   - Configure via `GITLAB_OMNIBUS_CONFIG` in docker-compose

## Maintenance

### Update GitLab

```bash
cd phase-2

# Pull latest image
docker compose -f docker-compose_gitlab.yml pull gitlab

# Recreate GitLab container
docker compose -f docker-compose_gitlab.yml up -d gitlab
```

### Update GitLab Runner

```bash
# Stop the runner service
sudo gitlab-runner stop

# Download latest version
curl -L --output /tmp/gitlab-runner "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"

# Replace the binary
sudo mv /tmp/gitlab-runner /usr/local/bin/gitlab-runner
sudo chmod +x /usr/local/bin/gitlab-runner

# Start the runner service
sudo gitlab-runner start

# Verify version
gitlab-runner --version
```

### Clean Up Old Build Artifacts

```bash
# Clean Docker images and containers
docker system prune -a

# Clean GitLab artifacts via UI:
# Admin Area → Settings → CI/CD → Continuous Integration
# Set "Default artifacts expiration"
```

## Resources

- [GitLab Documentation](https://docs.gitlab.com/)
- [GitLab Runner Documentation](https://docs.gitlab.com/runner/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Flutter CI/CD Best Practices](https://docs.flutter.dev/deployment/cd)
- [Docker Documentation](https://docs.docker.com/)

## License

See [LICENSE](LICENSE) file for details.

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review phase-specific README files (e.g., `phase-2/README-SSL.md`)
3. Consult official documentation for each component
4. Check Docker and GitLab logs for error messages
