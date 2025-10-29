# Start GitLab
cd ~/ci-cd/gitlab
docker compose up -d

# Wait for GitLab to be ready
sleep 60

# Get registration token from GitLab UI or API
# Then register runners:

# 1. Docker runner for general builds
docker exec -it gitlab-runner-docker gitlab-runner register \
  --non-interactive \
  --url "http://gitlab:80/" \
  --registration-token "YOUR_TOKEN" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --description "docker-runner" \
  --tag-list "docker,build" \
  --docker-network-mode "cicd-network"

# 2. Shell runner for Android emulator tests
docker exec -it gitlab-runner-shell gitlab-runner register \
  --non-interactive \
  --url "http://localhost/" \
  --registration-token "YOUR_TOKEN" \
  --executor "shell" \
  --description "android-emulator-runner" \
  --tag-list "android-emulator,integration"
