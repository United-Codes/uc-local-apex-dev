#!/usr/bin/env bash
# desc: Start the database and ORDS containers

set -e

source ./scripts/util/load_env.sh

$DOCKER_COMPOSE -f docker-compose.yml up -d
