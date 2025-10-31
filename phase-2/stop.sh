#!/bin/bash

# 1. Stop runners first (they depend on GitLab)
docker compose stop gitlab-runner-docker gitlab-runner-shell

# 2. Give runners a moment to gracefully stop
sleep 30

# 3. Stop GitLab gracefully
docker compose stop gitlab

# 4. Verify containers are stopped
docker compose ps

# You should see all containers with "Exited" status
