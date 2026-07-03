#!/usr/bin/env bash
# desc: Install APEX and apply dev-friendly DB defaults (run once after first DB start)

set -e

# --- Check for required non-default commands ---
MISSING_CMDS=()

for cmd in sql unzip; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING_CMDS+=("$cmd")
  fi
done

# A container engine (docker or podman) is required.
if [ -z "${CONTAINER_CLI:-}" ] \
   && ! command -v docker &>/dev/null \
   && ! command -v podman &>/dev/null; then
  MISSING_CMDS+=("docker or podman")
fi

# At least one of curl or wget is required (for APEX download)
if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
  MISSING_CMDS+=("curl or wget")
fi

if [ ${#MISSING_CMDS[@]} -gt 0 ]; then
  echo "ERROR: The following required commands are missing:" >&2
  for cmd in "${MISSING_CMDS[@]}"; do
    echo "  - $cmd" >&2
  done
  exit 1
fi
# --- End command check ---

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


./scripts/upgrade-apex.sh

ADMIN_PWD=$ORACLE_PASSWORD
echo "Setting the APEX Internal ADMIN password to the ORACLE_PASSWORD from .env (reused)"
if [ ! -f ./apex/apxchpwd.sql ]; then
  echo "ERROR: ./apex/apxchpwd.sql not found — APEX install may not have completed." >&2
  exit 1
fi
echo -e "ADMIN\nADMIN\n$ADMIN_PWD" | sql -name "$DB_CONN_NAME" @apex/apxchpwd.sql

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
