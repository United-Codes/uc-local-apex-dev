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

# Note: the heredoc below is unquoted, so bash expands anything with a $ in it.
# Keep prose comments out here, and never write an Oracle name that contains a
# dollar sign inside the heredoc without escaping it.
#
# The unified audit table is interval-partitioned by DAY, and Oracle's default
# _partition_large_extents=TRUE gives every partition segment an 8 MB initial
# extent. One day of auditing therefore costs 1 table partition + 4 LOB
# partitions (SQL_TEXT, SQL_BINDS, RLS_INFO, DP_CLOB_PARAMETERS) = ~41 MB,
# almost regardless of how many audit records that day produced. Measured on a
# real install: 41 partitions holding 1716 rows occupied 1693 MB.
#
# So audit_trail needs both a ceiling and the purge job further down. Its
# increment is 8m to match the extent size -- with next 2m every new LOB
# partition forces four separate extends.
sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on size unlimited

create tablespace audit_trail
  datafile 'audit01.dbf'
  size 20m
  autoextend on next 8m
  maxsize 1g;

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

-- Keep 7 days of unified audit records, on a rolling window.
--
-- This replaces a bare set_last_archive_timestamp(sysdate-7) call, which marked
-- records archivable but had no purge behind it and so never freed a byte.
--
-- dbms_audit_mgmt.create_purge_job is deliberately NOT used: it cannot advance
-- the last archive timestamp, so use_last_arch_timestamp=>TRUE purges up to a
-- frozen point forever and FALSE wipes the whole trail on every run. Neither
-- gives a rolling window. One scheduler job doing both calls does.
--
-- dbms_audit_mgmt.init_cleanup is NOT used either. It carries pragma deprecate
-- in 23.26.2, and is_cleanup_initialized raises ORA-46259 "not applicable for
-- UNIFIED_AUDIT_TRAIL". The unified trail needs no cleanup initialisation.
--
-- Measured effect of one run on a 44-day-old install: table partitions 41 -> 6,
-- segments 376 -> 61, allocated 1693 MB -> 267 MB. The reclaim comes from
-- dropping whole partitions, not from deleting rows -- deleted SecureFile LOB
-- space stays inside its segment. The freed space returns to the tablespace,
-- not to the operating system; shrink-space does that part.
begin
  dbms_scheduler.drop_job('UC_AUDIT_PURGE', force => true);
exception when others then
  null;
end;
/

begin
  dbms_scheduler.create_job(
    job_name        => 'UC_AUDIT_PURGE',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[begin
  dbms_audit_mgmt.set_last_archive_timestamp(
    audit_trail_type  => dbms_audit_mgmt.audit_trail_unified,
    last_archive_time => systimestamp - 7);
  dbms_audit_mgmt.clean_audit_trail(
    audit_trail_type        => dbms_audit_mgmt.audit_trail_unified,
    use_last_arch_timestamp => true);
end;]',
    start_date      => systimestamp,
    repeat_interval => 'FREQ=DAILY;BYHOUR=3;BYMINUTE=15',
    enabled         => true,
    auto_drop       => false,
    comments        => 'uc-local-apex-dev: keep 7 days of unified audit');
  dbms_output.put_line('created UC_AUDIT_PURGE');
exception when others then
  dbms_output.put_line('skip UC_AUDIT_PURGE: '||sqlerrm);
end;
/

create bigfile tablespace tbs_apex
  datafile 'tbs_apex.dbf'
  size 20m
  autoextend on next 20m
  maxsize 3g
;

-- Undo settings. The datafile ceiling itself comes from cap-tablespaces.sh
-- further down, so the ceiling policy lives in exactly one place.
--
-- Oracle's undo autotuning grows an autoextensible undo datafile to satisfy
-- undo_retention (the alert log says "Autotune of undo retention is turned on"
-- at every open). The Oracle image ships undo with no maxsize, so that growth is
-- unbounded. On Free edition it reached 3810 MB on a real install and pushed the
-- PDB past the 12 GB limit -- at which point the PDB will not open in ANY mode,
-- because ORA-12954 is raised before the open. "open read only" and
-- "open upgrade" fail identically, and nothing inside the PDB can be changed to
-- repair it.
--
-- 900 is the Oracle default. Set it explicitly so the intent is recorded and a
-- future change is a visible diff. Do not raise it: a higher value tells the
-- autotuner to grow the datafile harder, which is the failure being prevented.
alter system set undo_retention = 900 scope = both;

-- NOGUARANTEE is the default, and it is what makes the cap degrade gracefully
-- instead of hard-failing. Assert it, because RETENTION GUARANTEE would invert
-- the design above and turn every cap-hit into an ORA-30036.
begin
  for r in (select tablespace_name from dba_tablespaces
             where contents = 'UNDO' and retention = 'GUARANTEE')
  loop
    execute immediate 'alter tablespace '||r.tablespace_name||
      ' retention noguarantee';
    dbms_output.put_line('set noguarantee on '||r.tablespace_name);
  end loop;
end;
/
SQL

# Start from a known state instead of waiting for the first 03:15 run.
sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on
begin
  dbms_scheduler.run_job('UC_AUDIT_PURGE', use_current_session => true);
  dbms_output.put_line('initial audit purge done');
exception when others then
  dbms_output.put_line('skip initial audit purge: '||sqlerrm);
end;
/
SQL

# Give every datafile a size ceiling, so no single file can grow until the PDB
# passes the 12 GB Free-edition limit. This covers the tablespaces that the
# Oracle image creates -- undo and USERS ship with unbounded autoextend -- as
# well as any tablespace created above. The ceiling policy lives only in
# cap-tablespaces.sh, so there is one place to change it.
./scripts/cap-tablespaces.sh --apply -y


./scripts/upgrade-apex.sh

ADMIN_PWD=$ORACLE_PASSWORD
echo "Setting the APEX Internal ADMIN password to the ORACLE_PASSWORD from .env (reused)"
if [ ! -f ./apex/apxchpwd.sql ]; then
  echo "ERROR: ./apex/apxchpwd.sql not found — APEX install may not have completed." >&2
  exit 1
fi
echo -e "ADMIN\nADMIN\n$ADMIN_PWD" | sql -name "$DB_CONN_NAME" @apex/apxchpwd.sql

./scripts/disable-password-expiration.sh

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
