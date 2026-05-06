#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

$DOCKER_COMPOSE -f docker-compose.yml up -d
