#!/usr/bin/env bash

# special thanks to philipp salvisberg (https://github.com/United-Codes/uc-local-apex-dev/issues/5)

set -e

source ./scripts/util/load_env.sh

echo "Disabling archive logs"
docker exec "$CONTAINER_NAME" bash -c "sqlplus -S / as sysdba <<EOF
shutdown immediate;
startup mount;
alter database noarchivelog;
alter database open;
archive log list;
exit;
EOF"

echo "Removing archive logs"
docker exec "$CONTAINER_NAME" bash -c "cd /opt/oracle/product/26ai/dbhomeFree/dbs && rm arch1*.dbf"
