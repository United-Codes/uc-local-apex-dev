#!/usr/bin/env bash

docker exec -u oracle -it ${CONTAINER_NAME} bash -c 'cd /opt/oracle/oradata; mkdir -p datapump/import; mkdir -p datapump/export'

sql -name $DB_CONN_NAME <<SQL
  create or replace directory datapump_import_dir as '/opt/oracle/oradata/datapump/import';
  create or replace directory datapump_export_dir as '/opt/oracle/oradata/datapump/export';

  exit;
SQL

echo "created datapump directories"
