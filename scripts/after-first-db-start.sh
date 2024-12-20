#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/get_ws_settings.sh

# save sys connection
./scripts/util/save-sqlcl-connection.sh

# setup datapump directories
./scripts/util/create-datapump-directory.sh

echo "Configuring INTERNAL workspace settings"

# get workspace settings (extended session timeout, etc)
WS_SETTINGS=$(get_ws_settings "INTERNAL")

sql -name $DB_CONN_NAME <<SQL
  select user from dual;

  $WS_SETTINGS

  declare
    l_username varchar2(100) ;
  begin
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

    -- ACL to allow web service requests
    dbms_network_acl_admin.Append_host_ace(
      host => '*',
      ace => Xs$ace_type(
        privilege_list => Xs$name_list('connect')
      , principal_name => l_username
      , principal_type => xs_acl.ptype_db
      )
    );

    commit;

  end;
  / 

  commit;
SQL

./scripts/sync-backups-folder.sh
