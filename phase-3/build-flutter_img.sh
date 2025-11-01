#!/bin/bash

. ${PWD}/flutter.version

docker build -t flutter:${FLUTTER_VERSION} .
