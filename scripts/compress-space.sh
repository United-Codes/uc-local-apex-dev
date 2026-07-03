#!/usr/bin/env bash
# desc: Compress an existing schema's tablespace and give freed space back to the OS

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user_in_env.sh

# Enable Advanced Compression for a single app schema's tablespace and apply it
# to that schema's existing objects.
#
# create-user.sh gives every app user its own bigfile-free tablespace named
# tbs_<username>. This script:
#   1. Sets that tablespace's DEFAULTs so *new* segments are created compressed:
#        - tables: COMPRESS FOR OLTP   (advanced row compression; recompresses on DML)
#        - indexes: COMPRESS ADVANCED LOW (per-block prefix dedup, ~no read overhead)
#   2. Rebuilds the schema's *existing* tables (MOVE) and indexes (REBUILD) so the
#      data already in the tablespace is compressed too -- setting the default
#      alone never touches segments that already exist.
#
# Everything runs through the SYS connection ($DB_CONN_NAME): ALTER TABLESPACE
# needs the ALTER TABLESPACE privilege the app user doesn't have, and SYS can
# MOVE/REBUILD the schema's objects by owner-qualified name.
#
# MOVE/REBUILD are ONLINE and non-destructive (they rebuild a segment, never drop
# data) and idempotent (already-advanced-compressed objects are skipped), so this
# is safe to re-run. Per-object exception handling means an object that can't be
# moved (partitioned, IOT, a feature MOVE ONLINE rejects, ...) is reported and
# skipped without aborting the rest.
#
# Advanced Compression is included in Oracle Database Free, so there is no licence
# concern here.
#
# After rebuilding, the freed extents sit inside the tablespace -- the datafile on
# disk is still its old size. So this script then reclaims that space, reusing the
# proven shrink-space.sh recipe scoped to this one tablespace:
#   - dbms_space.shrink_tablespace compacts the segments, then
#   - in a SEPARATE connection, the datafile is resized down to its high-water
#     mark (the step that returns space to the OS). The separate connection is
#     mandatory: shrink_tablespace leaves transient blocks high in the file for
#     the rest of that session, so a same-session resize hits ORA-03297 and frees
#     nothing. See the matching note in shrink-space.sh.

if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name> [-y]"
  exit 1
fi
USERNAME=$1

# Check for -y flag (skip the confirmation prompt)
AUTO_YES=false
if [[ "$2" == "-y" ]]; then
  AUTO_YES=true
fi

USERNAME_UPPER=$(echo "$USERNAME" | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

if [[ $USERNAME_LOWER == "sys" ]]; then
  echo "Cannot compress the SYS schema"
  exit 1
fi

user_in_env "$USERNAME"

TBS="TBS_${USERNAME_UPPER}"

echo "Will set Advanced Compression defaults on tablespace $TBS and rebuild"
echo "schema $USERNAME_UPPER's existing tables (MOVE) and indexes (REBUILD)."

if [[ "$AUTO_YES" == "true" ]]; then
  echo "Auto-confirmed with -y."
  answer="y"
elif [ -t 0 ]; then
  read -r -p "Continue? (y/n) " answer
else
  answer="y"
fi

if [[ $answer != "y" ]] && [[ $answer != "Y" ]]; then
  echo "Stopping..."
  exit 0
fi

sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on size unlimited

prompt Tablespace usage before compression:
select round((select sum(bytes) from dba_segments   where tablespace_name = '$TBS')/1024/1024, 1) as used_mb,
       round((select sum(bytes) from dba_data_files where tablespace_name = '$TBS')/1024/1024, 1) as allocated_mb
  from dual;

prompt Setting tablespace compression defaults:

begin
  -- Set the TABLE and INDEX defaults in a SINGLE statement: each
  -- ALTER TABLESPACE ... DEFAULT replaces the whole default spec, so splitting
  -- this into two ALTERs would have the index clause silently reset the table
  -- default back to NOCOMPRESS. The DEFAULT keyword is also required before the
  -- INDEX clause (ALTER TABLESPACE ... INDEX COMPRESS ... alone raises ORA-02142).
  execute immediate 'ALTER TABLESPACE $TBS '||
    'DEFAULT TABLE COMPRESS FOR OLTP INDEX COMPRESS ADVANCED LOW';
  dbms_output.put_line('defaults set: TABLE COMPRESS FOR OLTP, INDEX COMPRESS ADVANCED LOW');
exception when others then
  dbms_output.put_line('skip tablespace defaults: '||sqlerrm);
end;
/

prompt Compressing existing tables (MOVE ONLINE):

begin
  for rec in (
    select t.owner, t.table_name
      from dba_tables t
     where t.owner = '$USERNAME_UPPER'
       and t.tablespace_name = '$TBS'
       and t.nested = 'NO'           -- nested-table storage is moved via its parent
       and t.iot_type is null        -- IOTs use a different MOVE syntax
       and t.temporary = 'N'
       -- skip what is already advanced-row-compressed so re-runs are cheap
       and not (t.compression = 'ENABLED' and t.compress_for = 'ADVANCED')
  )
  loop
    begin
      execute immediate 'ALTER TABLE "'||rec.owner||'"."'||rec.table_name||
        '" MOVE ONLINE ROW STORE COMPRESS ADVANCED';
      dbms_output.put_line('moved '||rec.table_name);
    exception when others then
      dbms_output.put_line('skip table '||rec.table_name||': '||sqlerrm);
    end;
  end loop;
end;
/

prompt Compressing existing indexes (REBUILD ONLINE):

begin
  for rec in (
    select i.owner, i.index_name
      from dba_indexes i
     where i.owner = '$USERNAME_UPPER'
       and i.tablespace_name = '$TBS'
       and i.index_type in ('NORMAL', 'NORMAL/REV', 'FUNCTION-BASED NORMAL')
       and i.partitioned = 'NO'      -- partitioned indexes rebuild per-partition
       and i.status = 'VALID'
       -- skip what is already advanced-compressed so re-runs are cheap
       and nvl(i.compression, 'DISABLED') <> 'ADVANCED LOW'
       -- single-column UNIQUE keys (most PK/UK indexes on an id column) can't be
       -- compressed with ADVANCED LOW -- nothing to dedup -- and raise ORA-25193.
       -- Filter them out so the log shows only real work instead of skip noise.
       and not (i.uniqueness = 'UNIQUE'
                and (select count(*) from dba_ind_columns c
                      where c.index_owner = i.owner
                        and c.index_name = i.index_name) = 1)
  )
  loop
    begin
      execute immediate 'ALTER INDEX "'||rec.owner||'"."'||rec.index_name||
        '" REBUILD ONLINE COMPRESS ADVANCED LOW';
      dbms_output.put_line('rebuilt '||rec.index_name);
    exception when others then
      dbms_output.put_line('skip index '||rec.index_name||': '||sqlerrm);
    end;
  end loop;
end;
/

prompt Compacting segments (dbms_space.shrink_tablespace):

begin
  dbms_space.shrink_tablespace('$TBS');
  dbms_output.put_line('shrank tablespace $TBS');
exception when others then
  dbms_output.put_line('skip shrink $TBS: '||sqlerrm);
end;
/

exit;
SQL

# Resize the datafile(s) down to the high-water mark in a SEPARATE connection --
# see the note at the top of this script for why a fresh session is required.
# Non-destructive: Oracle raises ORA-03297 if the target would truncate used data,
# so a too-small size is rejected (caught below) rather than losing anything. We
# re-read the HWM on each of a few attempts in case DML nudges it up between tries.
sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on size unlimited

prompt Resizing datafiles down to their high-water mark:

begin
  for rec in (
    select df.file_name, df.file_id, ts.block_size,
           round(df.bytes/1024/1024) cur_mb
      from dba_data_files df
      join dba_tablespaces ts on ts.tablespace_name = df.tablespace_name
     where df.tablespace_name = '$TBS'
  )
  loop
    declare
      l_hwm    number;
      l_target number;
      l_done   boolean := false;
    begin
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

prompt Tablespace usage after compression:
select round((select sum(bytes) from dba_segments   where tablespace_name = '$TBS')/1024/1024, 1) as used_mb,
       round((select sum(bytes) from dba_data_files where tablespace_name = '$TBS')/1024/1024, 1) as allocated_mb
  from dual;

exit;
SQL

echo ">>>>"
echo "Done. Compressed $USERNAME_UPPER's objects in $TBS and resized the datafile"
echo "down to its high-water mark."
