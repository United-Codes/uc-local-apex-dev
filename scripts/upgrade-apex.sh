#!/usr/bin/env bash
# desc: Download the latest APEX version and upgrade the installation

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/get_ws_settings.sh

echo "Downloading APEX"

# Only clear the download staging dir here. Do NOT wipe ./apex-images up front:
# if a later step fails, a pre-emptive delete leaves the running ORDS with no
# static files (/i/). apex-images is repopulated from the fresh ./apex only after
# apexins.sql succeeds (below).
rm -rf ./apex || true

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
# APEX install succeeded above -- now it is safe to refresh the served images.
# Clear the target's CONTENTS (not the dir itself) so removed/renamed files from
# an older version don't linger, while keeping the directory inode and its perms
# intact -- it is a live bind-mount source for the ORDS container.
mkdir -p ./apex-images
find ./apex-images -mindepth 1 -delete
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

    -- Instance-level APEX settings via the supported public API instead of
    -- poking wwv_flow_platform_prefs directly.
    apex_instance_admin.set_parameter('MAX_SESSION_IDLE_SEC', 604800);
    apex_instance_admin.set_parameter('MAX_SESSION_LENGTH_SEC', 604800);
    -- 9999 is the max ACCOUNT_LIFETIME_DAYS the API allows (validated against
    -- [1-9][0-9]{0,3}); ~27 years, i.e. effectively never for a dev env.
    apex_instance_admin.set_parameter('ACCOUNT_LIFETIME_DAYS', 9999);
    apex_instance_admin.set_parameter('MAX_APPLICATION_BACKUPS', 3);

    -- Relax the APEX site-admin password rule so the auto-generated
    -- alphanumeric ORACLE_PASSWORD (used as the INTERNAL ADMIN password by
    -- after-first-db-start.sh) is accepted by apxchpwd. This is a dev-only
    -- environment.
    apex_instance_admin.set_parameter('STRONG_SITE_ADMIN_PASSWORD', 'N');
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
