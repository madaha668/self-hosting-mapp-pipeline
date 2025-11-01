#!/bin/bash

. ${PWD}/flutter.version

#FIXME: set yours !!!
PUB_CACHE_DIR=${HOME}/oldhome/ci-cd/sample-projs/demo-app/pub-cache
GRADLE_CACHE_DIR=${HOME}/oldhome/ci-cd/sample-projs/demo-app/gradle

docker run --dns 8.8.8.8 -v ${PWD}:/build \
           -v ${PUB_CACHE_DIR}:/root/.pub-cache  \
           -v ${GRADLE_CACHE_DIR}:/root/.gradle  \
           --add-host=host.docker.internal:172.17.0.1 \
           -e ADB_SERVER_SOCKET=tcp:host.docker.internal:5037 \
           --workdir /build --rm -it flutter:${FLUTTER_VERSION} dart $*
