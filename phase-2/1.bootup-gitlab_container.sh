#!/bin/bash

source ../.sh-env

# Prepare
GITLAB_HOME=$WORKFLOW_HOME/ci-cd/gitlab/
mkdir -p $GITLAB_HOME
cp -f *.sh $GITLAB_HOME/
cp -f .env $GITLAB_HOME/
cp -f ./traefik-dynamic.yml       $GITLAB_HOME/
cp -f ./docker-compose_gitlab.yml $GITLAB_HOME/docker-compose.yml

# Launch Gitlab
cd $GITLAB_HOME && ./setup-with-ssl.sh

# Wait for GitLab to be ready
sleep 60
