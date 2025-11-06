#!/bin/bash

RUNNER_USER=gitlab-runner
RUNNER_GROUP=gitlab-runner

RUNNER_BIN=/usr/local/bin/gitlab-runner

#sudo curl -L --output ${RUNNER_BIN} "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"   

#sudo chown $RUNNER_USER:$RUNNER_GROUP ${RUNNER_BIN}
#sudo chmod +x 	     		      ${RUNNER_BIN}
#sudo chmod u+s       		      ${RUNNER_BIN}
sudo gitlab-runner install --user ${RUNNER_USER} --service gitlab-runner  --config /home/${RUNNER_USER}/.gitlab-runner/config.toml --working-directory /home/${RUNNER_USER}/ci-cd/working
#sudo gitlab-runner install --user ${RUNNER_USER}  --config /home/${RUNNER_USER}/.gitlab-runner/config.toml
sudo gitlab-runner start
