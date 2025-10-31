#!/bin/bash

source ../.sh-env

# Start GitLab
GITLAB_HOME=$WORKFLOW_HOME/ci-cd/gitlab/
cp -f ./docker-compose_gitlab.yml $GITLAB_HOME/docker-compose.yml
cd $GITLAB_HOME && bash start.sh

# Wait for GitLab to be ready
sleep 60
