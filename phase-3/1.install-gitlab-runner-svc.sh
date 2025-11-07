#!/bin/bash

source ../.sh-env

RUNNER_USER=$USER
RUNNER_GROUP=$USER

RUNNER_BIN=/usr/local/bin/gitlab-runner

sudo curl -L --output ${RUNNER_BIN} "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"   

sudo chmod +x 	     		      ${RUNNER_BIN}
sudo gitlab-runner install --user ${RUNNER_USER} --service gitlab-runner  --config /home/${RUNNER_USER}/.gitlab-runner/config.toml --working-directory ${WORKFLOW_HOME}/ci-cd/working
sudo gitlab-runner start
