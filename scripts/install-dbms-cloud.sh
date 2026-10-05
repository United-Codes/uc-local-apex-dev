#!/usr/bin/env bash
# desc: Install the DBMS_CLOUD package into the database

set -e

source ./scripts/util/load_env.sh

# DBMS_CLOUD lives in the common user C##CLOUD$SERVICE, so the CDB root shows it.
# Skip the long catcon run when a previous run already installed it. To reload
# the packages after an image change, use upgrade-dbms-cloud.sh.
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

if [ "$installed" = "1" ]; then
  echo "DBMS_CLOUD is already installed. Skipping the install scripts."
else
$CONTAINER_CLI exec "$CONTAINER_NAME" bash -c "
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
fi

echo "DBMS Cloud installation completed."


TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
echo "Downloading Oracle Cloud certificates to $TEMP_DIR"

curl -fsS -o "$TEMP_DIR/dbc_certs.tar" "https://objectstorage.us-phoenix-1.oraclecloud.com/p/KB63IAuDCGhz_azOVQ07Qa_mxL3bGrFh1dtsltreRJPbmb-VwsH2aQ4Pur2ADBMA/n/adwcdemo/b/CERTS/o/dbc_certs.tar"

tar -xf "$TEMP_DIR/dbc_certs.tar" -C "$TEMP_DIR"
rm "$TEMP_DIR/dbc_certs.tar"
echo "Certificates extracted to $TEMP_DIR"

# create wallet directory
DOCKER_IT_FLAGS=""
if [ -t 0 ]; then
  DOCKER_IT_FLAGS="-it"
fi

$CONTAINER_CLI exec -u oracle $DOCKER_IT_FLAGS "${CONTAINER_NAME}" bash -c 'cd /opt/oracle/oradata; mkdir -p wallets/ssl'

# copy certificates to wallet directory
$CONTAINER_CLI cp "$TEMP_DIR/." "${CONTAINER_NAME}:/opt/oracle/oradata/wallets/ssl/"

# fix ownership
$CONTAINER_CLI exec -u root "${CONTAINER_NAME}" chown -R oracle:oinstall /opt/oracle/oradata/wallets/ssl/

# add files to wallet
$CONTAINER_CLI exec -u oracle $DOCKER_IT_FLAGS "${CONTAINER_NAME}" bash -c "
set -e

added=0
skipped=0
cd /opt/oracle/oradata/wallets/ssl/
# A second run keeps the wallet that exists.
if [ ! -f ewallet.p12 ]; then
  orapki wallet create -wallet . -pwd $ORACLE_PASSWORD -auto_login
fi

# Check what certificate files we have
echo 'Available certificate files:'
find . -name '*.cer' -o -name '*.crt' -o -name '*.pem' | head -10

# Add certificate files to wallet
for cert_file in *.cer *.crt *.pem; do
  if [ -f \"\$cert_file\" ]; then
    # orapki rejects a certificate that is already in the wallet. That is not
    # a failure, so count it and go on.
    if orapki wallet add -wallet . -trusted_cert -cert \"\$cert_file\" -pwd $ORACLE_PASSWORD >/dev/null 2>&1; then
      added=\$((added + 1))
    else
      skipped=\$((skipped + 1))
    fi
  fi
done
echo \"Certificates added: \$added, skipped: \$skipped\"

orapki wallet display -wallet .
"

echo ""
echo "================"
echo "Wallet created and certificates added successfully."
echo "================"


# Network/wallet ACLs are per-PDB — grant them where DBMS_CLOUD is actually used.
sql -name "$DB_CONN_NAME" <<EOF
begin
  -- Allow all hosts for HTTP/HTTP_PROXY
  sys.dbms_network_acl_admin.append_host_ace(
    host =>'*',
    lower_port => 443,
    upper_port => 443,
    ace => xs\$ace_type(
    privilege_list => xs\$name_list('http', 'http_proxy'),
    principal_name => 'C##CLOUD\$SERVICE',
    principal_type => xs_acl.ptype_db)
  );

  dbms_network_acl_admin.append_wallet_ace(
        wallet_path => 'file:/opt/oracle/oradata/wallets/ssl',
        ace => xs\$ace_type(
            privilege_list =>xs\$name_list('use_client_certificates', 'use_passwords'),
            principal_name => 'C##CLOUD\$SERVICE',
            principal_type => xs_acl.ptype_db)
  );
end;
/

exit
EOF

# ssl_wallet is a database-wide property and must be set in the CDB root
# (ORA-65040 when run from a PDB).
sql sys/"$ORACLE_PASSWORD"@localhost:"$DBPORT"/FREE as SYSDBA <<EOF
alter database property set ssl_wallet='file:/opt/oracle/oradata/wallets/ssl';

exit
EOF

# Restart the whole instance (not just the PDB) from inside the container:
# a network connection cannot reconnect for startup after shutdown (ORA-12514).
$CONTAINER_CLI exec "$CONTAINER_NAME" bash -c 'source /home/oracle/.bashrc 2>/dev/null; $ORACLE_HOME/bin/sqlplus -S / as sysdba <<EOF
shutdown immediate;
startup;
alter pluggable database all open;
exit
EOF'

echo "Database restarted to apply wallet settings."

# Check the result: package valid in the PDB, wallet set, ACLs present.
sql -name "$DB_CONN_NAME" <<EOF
set pagesize 50 linesize 160
select object_type, status from dba_objects
 where owner = 'C##CLOUD\$SERVICE' and object_name = 'DBMS_CLOUD';
select count(*) as host_aces from dba_host_aces where principal = 'C##CLOUD\$SERVICE';
select count(*) as wallet_aces from dba_wallet_aces where principal = 'C##CLOUD\$SERVICE';
select property_value as ssl_wallet from database_properties where property_name = 'SSL_WALLET';
exit
EOF
