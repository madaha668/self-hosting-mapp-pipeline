#!/bin/bash

. ${PWD}/flutter.version

#FIXME: set yours !!!
PUB_CACHE_DIR=${HOME}/oldhome/ci-cd/sample-projs/demo-app/pub-cache
GRADLE_CACHE_DIR=${HOME}/oldhome/ci-cd/sample-projs/demo-app/gradle

#run as user instead of root
export UID_TGT=$(id -u)
export GID_TGT=$(id -g)
export KVM_GID=$(getent group kvm | cut -d: -f3)

docker run --dns 8.8.8.8 \
           --user ${UID_TGT}:${GID_TGT} \
           --group-add ${KVM_GID} \
           --device /dev/kvm \
           --env CI=true \
           -v ${PWD}:/build \
           -v ${PUB_CACHE_DIR}:/root/.pub-cache  \
           -v ${GRADLE_CACHE_DIR}:/root/.gradle  \
           --add-host=host.docker.internal:172.17.0.1 \
           -e ADB_SERVER_SOCKET=tcp:host.docker.internal:5037 \
           --workdir /build --rm -it flutter:${FLUTTER_VERSION} flutter $*
