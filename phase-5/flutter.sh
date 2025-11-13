#!/bin/bash

if [ -f ${PWD}/flutter.version ]; then
	. ${PWD}/flutter.version
else
	FLUTTER_VERSION=3.22.0
fi

if [ -f ${PWD}/../.sh-env ]; then
  source ../.sh-env
else
  WORKFLOW_HOME=${HOME}
fi

#FIXME: set yours !!!
PUB_CACHE_DIR=${WORKFLOW_HOME}/ci-cd/pub-cache
GRADLE_CACHE_DIR=${WORKFLOW_HOME}/ci-cd/gradle

#run as the default (first) user in the host instead of root
export UID_TGT=$(id -u)
export GID_TGT=$(id -g)
export KVM_GID=$(getent group kvm | cut -d: -f3)

# NOTE:
# add the following option to docker run cmdline if running in a physical host
#          --device /dev/kvm \

docker run --dns 8.8.8.8 \
           --user ${UID_TGT}:${GID_TGT} \
           --group-add ${KVM_GID} \
           --env CI=true \
           -v ${PWD}:/build \
           -v ${PUB_CACHE_DIR}:/home/ubuntu/.pub-cache  \
           -v ${GRADLE_CACHE_DIR}:/home/ubuntu/.gradle  \
           --device /dev/kvm \
           --add-host=host.docker.internal:172.17.0.1 \
           -e ADB_SERVER_SOCKET=tcp:host.docker.internal:5037 \
           --workdir /build --rm -i flutter:${FLUTTER_VERSION} flutter $*
