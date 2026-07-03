#!/usr/bin/env bash
# desc: Gracefully shut down the database, then stop the containers

set -e

source ./scripts/util/load_env.sh

echo "Gracefully stopping Oracle Database"
$CONTAINER_CLI exec $CONTAINER_NAME bash -c "echo 'shutdown immediate;
exit' | sqlplus / as sysdba && exit"

echo "Stopping Containers"
$DOCKER_COMPOSE -f docker-compose.yml stop
