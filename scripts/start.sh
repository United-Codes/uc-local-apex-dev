#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

docker-compose -f docker-compose.yml up -d
