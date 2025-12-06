#!/bin/bash
# Docker Compose compatibility helper
# Detects and uses the correct docker compose command

get_docker_compose_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
    else
        echo ""
    fi
}

# Export for use in other scripts
export DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)

# Validate
if [[ -z "$DOCKER_COMPOSE_CMD" ]]; then
    echo "错误: 未找到 Docker Compose" >&2
    echo "请安装: https://docs.docker.com/compose/install/" >&2
    exit 1
fi

# Usage in other scripts:
# source scripts/docker-compose-helper.sh
# $DOCKER_COMPOSE_CMD up -d
