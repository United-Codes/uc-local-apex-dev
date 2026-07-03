#!/usr/bin/env bash
# desc: Shrink tablespaces and datafiles to reclaim unused space

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

# Tier 2: drop the leftover old APEX engine schema (destructive, confirm-gated).
# An APEX upgrade (apexins.sql, see upgrade-apex.sh) installs the new version in
# a fresh APEX_<version> schema and leaves the prior one behind (e.g. APEX_240200
# alongside the live APEX_260100), wasting ~hundreds of MB in TBS_APEX. The public
# synonyms / apex_release already point only at the current schema, so the old one
# is dead weight. apxremov.sql is NOT used here: it removes the entire/current APEX.
# The supported way to remove just a prior version is DROP USER <old> CASCADE.
#
# APEX schemas are flagged oracle_maintained='Y', so a plain DROP USER raises
# ORA-28014 ("cannot drop administrative user or role") even as SYS. Setting
# "_oracle_script"=true for the session lifts that guard (this is how APEX's own
# removal scripts drop their schemas); it affects only this session.
#
# "Current" schema = the APEX_UTIL synonym owner (same lookup upgrade-apex.sh uses).
# The sentinel '###' prefix lets us strip the SQLcl banner from the captured output.
OLD_APEX=$(sql -name "$DB_CONN_NAME" <<'SQL' 2>/dev/null | grep '^###' | sed 's/^###//'
set heading off
set feedback off
set pagesize 0
select '###'||username
  from dba_users
 where regexp_like(username, '^APEX_[0-9]+$')
   and username <> (select creator from PUBLICSYN where sname = 'APEX_UTIL' fetch first 1 row only);
SQL
)

if [ -z "$OLD_APEX" ]; then
  echo "No old APEX version found."
else
  echo "Found old APEX schema(s):"
  echo "$OLD_APEX" | sed 's/^/  /'
  if [ -t 0 ]; then
    read -r -p "Drop old APEX schema(s) above with CASCADE (irreversible)? [y/N] " drop_ans
  else
    drop_ans="N"
    echo "Non-interactive mode: skipping old APEX drop for safety."
  fi

  if [[ $drop_ans == "y" ]] || [[ $drop_ans == "Y" ]]; then
    echo "Dropping old APEX schema(s)..."
    DROP_SQL=""
    for sch in $OLD_APEX; do
      DROP_SQL="$DROP_SQL
begin
  execute immediate 'DROP USER \"$sch\" CASCADE';
  dbms_output.put_line('dropped $sch');
exception when others then
  dbms_output.put_line('skip $sch: '||sqlerrm);
end;
/
"
    done
    sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on
alter session set "_oracle_script"=true;
$DROP_SQL
SQL
  else
    echo "Skipping old APEX drop."
  fi
fi

# Tier 3: reclaim space (non-destructive), in three steps:
#   1. SHRINK SPACE the FLOWS_FILES LOB to release dead space into the tablespace.
#   2. dbms_space.shrink_tablespace to compact segments.
#   (steps 1-2 share one connection)
#   3. In a fresh connection, resize each datafile down to its high-water mark --
#      the step that actually returns space to the OS (shrink_tablespace alone
#      usually can't trim the file). See the note above that block for why the
#      separate connection is required.
# AUDIT_TRAIL is included alongside the TBS_%/UNDOTBS% tablespaces. We first
# SHRINK SPACE the FLOWS_FILES file-repository
# LOB: it is a SECUREFILE LOB whose dead space (deleted/replaced app imports &
# uploads) is trapped *inside* the segment, so shrink_tablespace alone cannot
# reclaim it. Shrinking the LOB releases that space back into TBS_APEX first, then
# the tablespace shrink resizes the datafile down. LOB shrink is online and
# non-destructive (it compacts, never deletes live content).
sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on

prompt Space usage before shrinking:
SELECT
    ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS current_gb
FROM dba_data_files
;

prompt Shrinking FLOWS_FILES LOB:

begin
  for rec in (
    select owner, table_name, column_name
      from dba_lobs
     where owner = 'FLOWS_FILES'
       and table_name = 'WWV_FLOW_FILE_OBJECTS\$'
       and tablespace_name = 'TBS_APEX'
  )
  loop
    begin
      execute immediate 'ALTER TABLE "'||rec.owner||'"."'||rec.table_name||
        '" MODIFY LOB ("'||rec.column_name||'") (SHRINK SPACE)';
      dbms_output.put_line('shrank lob '||rec.table_name||'.'||rec.column_name);
    exception when others then
      dbms_output.put_line('skip lob '||rec.table_name||'.'||rec.column_name||': '||sqlerrm);
    end;
  end loop;
end;
/

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
SQL

# The resize MUST run in a SEPARATE connection from the shrink_tablespace block
# above. shrink_tablespace's segment relocations leave transient blocks high in
# the datafile that linger for the rest of that session, so a resize issued in
# the same connection hits ORA-03297 and reclaims nothing (observed: even a
# resize to 100 MB below the current size failed). A fresh connection sees the
# settled high-water mark, and the resize then succeeds.
#
# Resizing each datafile to just above its highest-used block is what actually
# returns space to the OS (shrink_tablespace alone usually can't trim the file).
# Non-destructive: Oracle raises ORA-03297 if the target would truncate used
# data, so a too-small size is rejected (caught below), never lossy. We re-read
# the HWM on each of a few attempts in case concurrent DML nudges it up.
sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on

prompt Resizing datafiles down to their high-water mark:

begin
  for rec in (
    select df.file_name, df.file_id, ts.block_size,
           round(df.bytes/1024/1024) cur_mb
      from dba_data_files df
      join dba_tablespaces ts on ts.tablespace_name = df.tablespace_name
     where (df.tablespace_name like 'TBS_%'
         or df.tablespace_name like 'UNDOTBS%'
         or df.tablespace_name = 'AUDIT_TRAIL')
       and df.bytes/1024/1024 >= 64   -- skip tiny per-schema datafiles, not worth it
  )
  loop
    declare
      l_hwm    number;
      l_target number;
      l_done   boolean := false;
    begin
      -- Re-query the high-water mark on every attempt: concurrent DML (e.g. APEX
      -- log tables) can push it up between tries, so we chase the real value
      -- rather than blindly bumping a fixed amount.
      for i in 1 .. 5 loop
        select max(block_id + blocks) into l_hwm
          from dba_extents where file_id = rec.file_id;
        l_target := ceil((l_hwm * rec.block_size)/1024/1024) + 2;
        exit when l_target >= rec.cur_mb - 8;   -- nothing meaningful to reclaim
        begin
          execute immediate 'alter database datafile '''||rec.file_name||
            ''' resize '||l_target||'M';
          dbms_output.put_line('resized '||rec.file_name||' from '||
            rec.cur_mb||'M to '||l_target||'M');
          l_done := true;
          exit;
        exception
          when others then
            if sqlcode = -3297 then
              null;   -- HWM drifted up under DML; loop re-reads it and retries
            else
              dbms_output.put_line('skip resize '||rec.file_name||': '||sqlerrm);
              exit;
            end if;
        end;
      end loop;

      if not l_done and l_target < rec.cur_mb - 8 then
        dbms_output.put_line('could not shrink '||rec.file_name||
          ' below '||rec.cur_mb||'M (used data sits high in the file)');
      end if;
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

echo "This only reclaims unused space. To also shrink the data itself, enable"
echo "Advanced Compression on a schema's tablespace: compress-space <schema>"

echo "Thanks to Connor McDonald for his blog post on space efficiently using the Free Edition: https://connor-mcdonald.com/2023/12/18/the-ultimate-database-free-edition/"

echo "If you are using Vector Indexes, take a look at Connor McDonald's blog post on partition_large_extents: https://connor-mcdonald.com/2025/03/10/vectors-in-oracle-database-23ai-free/"
