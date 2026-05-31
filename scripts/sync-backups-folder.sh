#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

chmod -R 777 ./backups/import
$CONTAINER_CLI cp ./backups/import ${CONTAINER_NAME}:/opt/oracle/oradata/datapump/
#$CONTAINER_CLI exec -u oracle -it ${CONTAINER_NAME} bash -c 'chown -R $(id -u):$(id -g) /opt/oracle/oradata/datapump/import'

$CONTAINER_CLI cp ${CONTAINER_NAME}:/opt/oracle/oradata/datapump/export/ ./backups/

echo "synced backups folder"
