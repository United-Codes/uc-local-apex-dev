#!/usr/bin/env bash

DOCKER_IT_FLAGS=""
if [ -t 0 ]; then
  DOCKER_IT_FLAGS="-it"
fi

docker exec -u oracle $DOCKER_IT_FLAGS "${CONTAINER_NAME}" bash -c 'cd /opt/oracle/oradata; mkdir -p datapump/import; mkdir -p datapump/export'

sql -name "$DB_CONN_NAME" <<SQL
  select user from dual;

  create or replace directory datapump_import_dir as '/opt/oracle/oradata/datapump/import';
  create or replace directory datapump_export_dir as '/opt/oracle/oradata/datapump/export';

  exit;
SQL

echo "created datapump directories"
