#!/bin/bash

# parameter validation#1
if [ $# -lt 2 ]; then
    echo "Usage: $0 <executor_type> <runner_token>"
    echo "  executor_type: 'docker' or 'shell'"
    echo "  runner_token: GitLab runner registration token"
    exit 1
fi

EXECUTOR_TYPE="$1"
RUNNER_TOKEN="$2"

# validation step#2
if [[ "$EXECUTOR_TYPE" != "docker" && "$EXECUTOR_TYPE" != "shell" ]]; then
    echo "Error: executor_type must be 'docker' or 'shell'"
    exit 1
fi

# common args
COMMON_ARGS="
    --non-interactive 
    --url 'https://gitlab.local/' 
    --token $RUNNER_TOKEN 
    --name ${EXECUTOR_TYPE}-runner"

# runner as docker or shell
if [ "$EXECUTOR_TYPE" = "docker" ]; then
    COMMON_ARGS+='
        --executor docker 
        --docker-image "alpine:latest" 
        --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" 
    '
    CONTAINER_NAME=gitlab-runner-docker
else  # shell
    COMMON_ARGS+='
        --executor shell
    '
    CONTAINER_NAME=gitlab-runner-docker
fi

# register it
echo ${COMMON_ARGS[@]}
gitlab-runner register ${COMMON_ARGS[@]}
#docker exec -it $CONTAINER_NAME gitlab-runner register "${COMMON_ARGS[@]}"
