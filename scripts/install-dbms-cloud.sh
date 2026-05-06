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


TEMP_DIR=$(mktemp -d)
echo "Downloading Oracle Cloud certificates to $TEMP_DIR"

curl -o "$TEMP_DIR/dbc_certs.tar" "https://objectstorage.us-phoenix-1.oraclecloud.com/p/KB63IAuDCGhz_azOVQ07Qa_mxL3bGrFh1dtsltreRJPbmb-VwsH2aQ4Pur2ADBMA/n/adwcdemo/b/CERTS/o/dbc_certs.tar"

cd "$TEMP_DIR"
tar -xf dbc_certs.tar
rm dbc_certs.tar
echo "Certificates extracted to $TEMP_DIR"

# create wallet directory
DOCKER_IT_FLAGS=""
if [ -t 0 ]; then
  DOCKER_IT_FLAGS="-it"
fi

docker exec -u oracle $DOCKER_IT_FLAGS "${CONTAINER_NAME}" bash -c 'cd /opt/oracle/oradata; mkdir -p wallets/ssl'

# copy certificates to wallet directory
docker cp "$TEMP_DIR/." "${CONTAINER_NAME}:/opt/oracle/oradata/wallets/ssl/"

# fix ownership
docker exec -u root "${CONTAINER_NAME}" chown -R oracle:oinstall /opt/oracle/oradata/wallets/ssl/

# add files to wallet
docker exec -u oracle $DOCKER_IT_FLAGS "${CONTAINER_NAME}" bash -c "
set -e

cd /opt/oracle/oradata/wallets/ssl/
orapki wallet create -wallet . -pwd $ORACLE_PASSWORD -auto_login

# Check what certificate files we have
echo 'Available certificate files:'
find . -name '*.cer' -o -name '*.crt' -o -name '*.pem' | head -10

# Add certificate files to wallet
for cert_file in *.cer *.crt *.pem; do
  if [ -f \"\$cert_file\" ]; then
    echo \"Adding certificate: \$cert_file\"
    orapki wallet add -wallet . -trusted_cert -cert \"\$cert_file\" -pwd $ORACLE_PASSWORD
  fi
done

orapki wallet display -wallet .
"

# delete temp folder
rm -rf "$TEMP_DIR"

echo ""
echo "================"
echo "Wallet created and certificates added successfully."
echo "================"


sql sys/"$ORACLE_PASSWORD"@localhost:1521/FREE as SYSDBA <<EOF
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

alter database property set ssl_wallet='file:/opt/oracle/oradata/wallets/ssl'


exit
EOF

sql -name local-23ai-sys <<EOF
  shutdown immediate;
  startup;

  exit
EOF

echo "Database restarted to apply wallet settings."
