#!/usr/bin/env bash
# desc: Reload the DBMS_CLOUD packages after a change of the database image

set -e

# A change of the database image does not upgrade DBMS_CLOUD. The packages stay
# at the release update that installed them, and the image ships newer code.
# This script runs the install scripts of Oracle again. They use CREATE OR
# REPLACE, so one run is safe to repeat.
#
# It does NOT touch the wallet, the certificates or the network ACLs, and it does
# not restart the database. install-dbms-cloud.sh does those steps one time.
#
# If DBMS_CLOUD is not installed, this script stops. A first install needs
# install-dbms-cloud.sh, which also creates the wallet and the ACLs.

source ./scripts/util/load_env.sh

# DBMS_CLOUD lives in the common user C##CLOUD$SERVICE, so the CDB root shows it.
installed=$($CONTAINER_CLI exec "$CONTAINER_NAME" bash -c '
source /home/oracle/.bashrc 2>/dev/null
$ORACLE_HOME/bin/sqlplus -S / as sysdba <<EOF
set heading off feedback off pagesize 0 verify off
select count(*) from dba_objects
 where owner = '"'"'C##CLOUD\$SERVICE'"'"'
   and object_name = '"'"'DBMS_CLOUD'"'"'
   and object_type = '"'"'PACKAGE BODY'"'"';
exit
EOF
' | tr -d '[:space:]')

if [ "$installed" != "1" ]; then
  echo "Error: DBMS_CLOUD is not installed in the database." >&2
  echo "Run './local-26ai.sh install-dbms-cloud' for the first install." >&2
  exit 1
fi

echo "DBMS_CLOUD is installed. Reloading the packages."

$CONTAINER_CLI exec "$CONTAINER_NAME" bash -c "
set -e
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

echo "DBMS_CLOUD upgrade completed."
