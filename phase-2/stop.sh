#!/bin/bash

# 1. Stop runners first (they depend on GitLab)
#echo "Stopping GitLab runners..."
#docker compose stop gitlab-runner-docker gitlab-runner-shell
# 1. Stop blackhole-404 to disable self signup
echo "Stopping Blackhole-404 ..."
docker compose stop blackhole-404

# 2. Give runners a moment to gracefully stop
sleep 30

# 3. Stop GitLab gracefully
echo "Stopping GitLab..."
docker compose stop gitlab

# 4. Give GitLab time to shut down
sleep 10

# 5. Stop Traefik last (reverse proxy)
echo "Stopping Traefik..."
docker compose stop traefik

# 6. Verify containers are stopped
docker compose ps

echo ""
echo "✅ All services stopped successfully!"
