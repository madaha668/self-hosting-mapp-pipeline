#!/bin/bash

# 1. Start GitLab first (let it fully initialize)
docker compose up -d gitlab

# 2. Wait for GitLab to be healthy (check every 5 seconds)
echo "Waiting for GitLab to be healthy..."
while ! docker exec gitlab curl -sf http://localhost:80/-/health > /dev/null 2>&1; do
  echo "  GitLab starting... (waiting for health check)"
  sleep 10
done
echo "✅ GitLab is healthy"

# 3. Start runners
docker compose up -d gitlab-runner-docker gitlab-runner-shell

# 4. Verify all containers are running
sleep 30
docker compose ps

# Should show all containers with "Up" status
