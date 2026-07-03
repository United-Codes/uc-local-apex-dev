#!/usr/bin/env bash
# desc: Download the latest APEX version and upgrade the installation

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/get_ws_settings.sh

echo "Downloading APEX"

rm -rf ./apex || true
rm -rf ./apex-images || true

APEX_URL="https://download.oracle.com/otn_software/apex/apex-latest.zip"
if command -v curl >/dev/null 2>&1; then
  curl -fLO "$APEX_URL"
elif command -v wget >/dev/null 2>&1; then
  wget "$APEX_URL"
else
  echo "Error: neither curl nor wget is installed. Please install one of them and re-run." >&2
  exit 1
fi
unzip apex-latest.zip
rm apex-latest.zip
rm -rf ./META-INF || true

echo "Installing APEX"

cd ./apex || exit 1

sql -name "$DB_CONN_NAME" <<SQL
@apexins.sql TBS_APEX TBS_APEX TEMP /i/
exit;
SQL

cd ..

echo "Configure APEX images"
mkdir -p ./apex-images
cp -R ./apex/images/. ./apex-images/

echo "Configuring INTERNAL workspace settings"

# get workspace settings (extended session timeout, etc)
WS_SETTINGS=$(get_ws_settings "INTERNAL")

sql -name "$DB_CONN_NAME" <<SQL
  select user from dual;

  declare
    l_username varchar2(100) ;
  begin
    $WS_SETTINGS

    select creator
      into l_username
      from PUBLICSYN where SNAME = 'APEX_UTIL'
     fetch first 1 row only;

    execute IMMEDIATE ' update ' || l_username || q'!.wwv_flow_platform_prefs
        set VALUE = 604800
      where NAME = 'MAX_SESSION_IDLE_SEC'
    !';
    commit;

    execute IMMEDIATE ' update ' || l_username || q'!.wwv_flow_platform_prefs
        set VALUE = 604800
      where NAME = 'MAX_SESSION_LENGTH_SEC'
    !';
    commit;

    execute IMMEDIATE ' update ' || l_username || q'!.wwv_flow_platform_prefs
        set VALUE = 10000
      where NAME = 'ACCOUNT_LIFETIME_DAYS'
    !';

    execute IMMEDIATE ' update ' || l_username || q'!.wwv_flow_platform_prefs
        set VALUE = 3
      where NAME = 'MAX_APPLICATION_BACKUPS'
    !';
    commit;

    -- Relax the APEX site-admin password rule so the auto-generated
    -- alphanumeric ORACLE_PASSWORD (used as the INTERNAL ADMIN password by
    -- after-first-db-start.sh) is accepted by apxchpwd. This is a dev-only
    -- environment.
    execute IMMEDIATE ' update ' || l_username || q'!.wwv_flow_platform_prefs
        set VALUE = 'N'
      where NAME = 'STRONG_SITE_ADMIN_PASSWORD'
    !';
    commit;

    -- ACL to allow web service requests
    dbms_network_acl_admin.Append_host_ace(
      host => '*',
      ace => Xs\$ace_type(
        privilege_list => Xs\$name_list('connect')
      , principal_name => l_username
      , principal_type => xs_acl.ptype_db
      )
    );

    commit;

  end;
  /

  commit;
SQL
