#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

echo "Gracefully stopping Oracle Database"
docker exec $CONTAINER_NAME bash -c "echo 'shutdown immediate;
exit' | sqlplus / as sysdba && exit"

echo "Stopping Containers"
docker-compose -f docker-compose.yml stop
