#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh


docker exec "$CONTAINER_NAME" bash -c "
\$ORACLE_HOME/perl/bin/perl \$ORACLE_HOME/rdbms/admin/catcon.pl \
  -u sys/$ORACLE_PASSWORD \
  --force_pdb_mode 'READ WRITE' \
  -b dbms_cloud_install \
  -d \$ORACLE_HOME/rdbms/admin/ \
  -l /tmp \
  catclouduser.sql

\$ORACLE_HOME/perl/bin/perl \$ORACLE_HOME/rdbms/admin/catcon.pl \
  -u sys/$ORACLE_PASSWORD \
  --force_pdb_mode 'READ WRITE' \
  -b dbms_cloud_install \
  -d \$ORACLE_HOME/rdbms/admin/ \
  -l /tmp \
  dbms_cloud_install.sql
"

echo "DBMS Cloud installation completed."
