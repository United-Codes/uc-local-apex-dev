#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

# The AUDIT_TRAIL datafile can autoextend to several GB during a burst of audit
# activity and never shrink back. Two independent levers reclaim that space:
#   1. Purge old audit records (deletes audit history; optional, below).
#   2. Shrink the tablespace (compacts segments + resizes the datafile down).
#
# dbms_space.shrink_tablespace can relocate the internal AUD$UNIFIED partitions
# that ALTER TABLE / DROP TABLESPACE cannot touch from inside a PDB (those raise
# ORA-65040), so a plain shrink is the reliable, non-destructive fix.

# Optional Tier 1: purge audit records. after-first-db-start.sh marks records
# archivable via set_last_archive_timestamp but never calls clean_audit_trail,
# so they accumulate. Each type is purged in its own block with an exception
# handler so a type that needs init_cleanup (or has nothing to purge) does not
# abort the rest.
if [ -t 0 ]; then
  read -r -p "Purge audit records first (deletes audit history, frees audit data)? [Y/n] " purge_ans
else
  purge_ans="Y"
fi

if [[ $purge_ans == "n" ]] || [[ $purge_ans == "N" ]]; then
  echo "Skipping audit purge."
else
  echo "Purging audit records..."
  sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on
begin
  dbms_audit_mgmt.set_last_archive_timestamp(
    audit_trail_type  => dbms_audit_mgmt.audit_trail_unified,
    last_archive_time => systimestamp);
  dbms_audit_mgmt.clean_audit_trail(
    audit_trail_type        => dbms_audit_mgmt.audit_trail_unified,
    use_last_arch_timestamp => true);
  dbms_output.put_line('unified purge done');
exception when others then
  dbms_output.put_line('unified purge skipped: '||sqlerrm);
end;
/

begin
  dbms_audit_mgmt.set_last_archive_timestamp(
    audit_trail_type  => dbms_audit_mgmt.audit_trail_aud_std,
    last_archive_time => systimestamp);
  dbms_audit_mgmt.clean_audit_trail(
    audit_trail_type        => dbms_audit_mgmt.audit_trail_aud_std,
    use_last_arch_timestamp => true);
  dbms_output.put_line('aud_std purge done');
exception when others then
  dbms_output.put_line('aud_std purge skipped: '||sqlerrm);
end;
/

begin
  dbms_audit_mgmt.set_last_archive_timestamp(
    audit_trail_type  => dbms_audit_mgmt.audit_trail_fga_std,
    last_archive_time => systimestamp);
  dbms_audit_mgmt.clean_audit_trail(
    audit_trail_type        => dbms_audit_mgmt.audit_trail_fga_std,
    use_last_arch_timestamp => true);
  dbms_output.put_line('fga_std purge done');
exception when others then
  dbms_output.put_line('fga_std purge skipped: '||sqlerrm);
end;
/
SQL
fi

# Tier 2: shrink tablespaces (non-destructive; compacts segments and resizes
# the datafiles down to the high-water mark). AUDIT_TRAIL is included alongside
# the TBS_%/UNDOTBS% tablespaces.
sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on

prompt Space usage before shrinking:
SELECT
    ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS current_gb
FROM dba_data_files
;

prompt Shrinking tablespaces:

begin
  for rec in (
    select tablespace_name
      from user_tablespaces
     where tablespace_name like 'TBS_%'
        or tablespace_name like 'UNDOTBS%'
        or tablespace_name = 'AUDIT_TRAIL'
  )
  loop
    begin
      dbms_space.shrink_tablespace(rec.tablespace_name);
    exception when others then
      dbms_output.put_line('skip '||rec.tablespace_name||': '||sqlerrm);
    end;
  end loop;
end;
/

prompt Space usage after shrinking:
SELECT
    ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS current_gb
FROM dba_data_files
;
SQL

echo "Resource to further optimize space usage: https://connor-mcdonald.com/2023/12/18/the-ultimate-database-free-edition/"
