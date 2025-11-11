#!/bin/bash

# 1. Start Traefik first (reverse proxy)
echo "Starting Traefik..."
docker compose up -d traefik

# 2. Wait for Traefik to be ready
echo "Waiting for Traefik to be healthy..."
sleep 5
while ! docker exec traefik traefik healthcheck --ping > /dev/null 2>&1; do
  echo "  Traefik starting... (waiting for health check)"
  sleep 5
done
echo "✅ Traefik is healthy"

# 3. Start GitLab (let it fully initialize)
echo "Starting GitLab..."
docker compose up -d gitlab

# 4. Wait for GitLab to be healthy
echo "Waiting for GitLab to be healthy..."
while ! docker exec gitlab curl -sf http://localhost:80/-/health > /dev/null 2>&1; do
  echo "  GitLab starting... (waiting for health check)"
  sleep 10
done
echo "✅ GitLab is healthy"

# 5. Start runners
#echo "Starting GitLab runners..."
#docker compose up -d gitlab-runner-docker gitlab-runner-shell
# 5. Start blackhole-404 to disable self signup
echo "Starting Blackhole-404 ..."
docker compose up -d blackhole-404

# 6. Verify all containers are running
sleep 30
docker compose ps

echo ""
echo "✅ All services started successfully!"
echo "GitLab is available at: https://gitlab.local"
echo "Traefik dashboard: http://localhost:8080"
