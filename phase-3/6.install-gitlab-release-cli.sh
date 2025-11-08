#!/bin/bash

RELEASE_CLI=release-cli-linux-amd64
wget https://gitlab.com/gitlab-org/release-cli/-/releases/v0.24.0/downloads/bin/${RELEASE_CLI}
chmod +x $RELEASE_CLI
sudo mv -f $RELEASE_CLI /usr/local/bin/release-cli
