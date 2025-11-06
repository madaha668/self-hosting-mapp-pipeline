#!/bin/bash

. ${PWD}/flutter.version

#FIXME: set yours !!!
PUB_CACHE_DIR=${HOME}/ci-cd/pub-cache
GRADLE_CACHE_DIR=${HOME}/ci-cd/gradle

#run as user instead of root
export UID_TGT=$(id -u)
export GID_TGT=$(id -g)
export KVM_GID=$(getent group kvm | cut -d: -f3)

#          --device /dev/kvm \
docker run --dns 8.8.8.8 \
           --user ${UID_TGT}:${GID_TGT} \
           --group-add ${KVM_GID} \
           --env CI=true \
           -v ${PWD}:/build \
           -v ${PUB_CACHE_DIR}:/home/ubuntu/.pub-cache  \
           -v ${GRADLE_CACHE_DIR}:/home/ubuntu/.gradle  \
           --add-host=host.docker.internal:172.17.0.1 \
           -e ADB_SERVER_SOCKET=tcp:host.docker.internal:5037 \
           --workdir /build --rm -i flutter:${FLUTTER_VERSION} flutter $*
