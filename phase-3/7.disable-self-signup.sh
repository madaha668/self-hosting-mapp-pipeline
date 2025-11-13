#!/bin/bash

docker exec gitlab gitlab-rails runner "::Gitlab::CurrentSettings.update!(signup_enabled: false)"

