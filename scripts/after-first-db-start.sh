#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/get_ws_settings.sh

# save sys connection
./scripts/util/save-sqlcl-connection.sh

# setup datapump directories
./scripts/util/create-datapump-directory.sh

# optimize DB for space usage based on Connors blog post: https://connor-mcdonald.com/2023/12/18/the-ultimate-database-free-edition/

sql -name "$DB_CONN_NAME" <<SQL
create tablespace audit_trail 
  datafile 'audit01.dbf' 
  size 20m 
  autoextend on next 2m;

begin
dbms_audit_mgmt.set_audit_trail_location(
   audit_trail_type=>dbms_audit_mgmt.audit_trail_aud_std,
   audit_trail_location_value=>'AUDIT_TRAIL');
end;
/

begin
dbms_audit_mgmt.set_audit_trail_location(
   audit_trail_type=>dbms_audit_mgmt.audit_trail_fga_std,
   audit_trail_location_value=>'AUDIT_TRAIL');
end;
/

begin
dbms_audit_mgmt.set_audit_trail_location(
   audit_trail_type=>dbms_audit_mgmt.audit_trail_db_std,
   audit_trail_location_value=>'AUDIT_TRAIL');
end;
/

begin
dbms_audit_mgmt.set_audit_trail_location(
   audit_trail_type=>dbms_audit_mgmt.audit_trail_unified,
   audit_trail_location_value=>'AUDIT_TRAIL');
end;
/

exec dbms_workload_repository.modify_baseline_window_size(window_size =>7); 
exec dbms_workload_repository.modify_snapshot_settings(retention=>7*1440);

exec dbms_stats.alter_stats_history_retention(7);
exec dbms_scheduler.set_scheduler_attribute('log_history',7);

begin
dbms_audit_mgmt.set_last_archive_timestamp(
   audit_trail_type=>dbms_audit_mgmt.audit_trail_unified,
   last_archive_time=>sysdate-7);
end;
/

create bigfile tablespace tbs_apex 
  datafile 'tbs_apex.dbf' 
  size 20m 
  autoextend on next 20m 
  maxsize 3g
;
SQL


echo "Downloading APEX"

rm -rf ./apex || true
rm -rf ./apex-images || true

wget https://download.oracle.com/otn_software/apex/apex-latest.zip
unzip apex-latest.zip
rm apex-latest.zip
rm -rf ./META-INF || true

echo "Installing APEX"

cd ./apex || exit 1
 
sql -name "$DB_CONN_NAME" @apexins.sql TBS_APEX TBS_APEX TEMP /i/

cd ..

echo "Configure APEX images"
cp -r ./apex/images/ ./apex-images/

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

read -r -p "Enter the APEX Internal ADMIN password [Welcome_1]: " ADMIN_PWD
ADMIN_PWD=${ADMIN_PWD:-Welcome_1}
echo "Changing Internal ADMIN password to $ADMIN_PWD"
echo -e "ADMIN\nADMIN\n$ADMIN_PWD" | sql -name "$DB_CONN_NAME" @apxchpwd.sql

./scripts/sync-backups-folder.sh

if [ -t 0 ]; then
  read -r -p "Do you want to disable archive logs (recommended if this is just a dev environment)? [Y/n] " answer
else
  answer="Y"
fi

if [[ $answer == "n" ]] || [[ $answer == "N" ]]; then
  echo "Keeping archive logs enabled"
else
  ./scripts/disable-archive-logs.sh
fi
