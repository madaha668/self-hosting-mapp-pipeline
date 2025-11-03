#!/bin/bash





. ${PWD}/flutter.version

docker build \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  -t flutter:${FLUTTER_VERSION} .
