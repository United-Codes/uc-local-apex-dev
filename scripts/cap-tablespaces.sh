#!/usr/bin/env bash
# desc: Give every datafile a size ceiling so one file cannot fill the 12GB limit

set -e

# The Free edition allows 12 GB of datafiles per PDB. Go over it and the PDB will
# not open again in ANY mode: ORA-12954 is raised inside the open path (ktslnfy_pdb)
# BEFORE the container opens, so "open read only" and "open upgrade" fail
# identically, and no statement issued inside the PDB can reduce its size. The
# only way back in is manual surgery with the CDB in MOUNT state.
#
# The Oracle image ships undo, SYSTEM, SYSAUX and USERS with no maxsize, and
# earlier versions of this project created audit_trail and every per-schema
# tablespace the same way. On one real install the undo datafile autoextended to
# 3810 MB unobserved and crossed the limit by itself.
#
# This script gives each datafile a ceiling. A ceiling is not a reservation: the
# ceilings deliberately add up to more than 12 GB, and they do NOT keep the total
# under the limit. What they guarantee is that no single file can silently absorb
# all the remaining headroom. A runaway then hits ORA-01653 (or ORA-30036 for
# undo) in one session, the database stays open, and every other schema keeps
# working. Keeping the total down is the job of `used-space` and `shrink-space`.
#
# New installs get these ceilings at creation time from after-first-db-start.sh
# and create-user.sh. This script exists for installs created before that, which
# never re-run after-first-db-start.sh (install.sh skips it once APEX is present).

usage() {
  cat <<'USAGE'
Usage: scripts/cap-tablespaces.sh [options]

  --check      Report the datafiles that have no ceiling. Read-only. The default.
  --apply      Apply the ceilings.
  --summary    Read-only, machine-readable "key=value" lines only.
  -y, --yes    Do not ask for confirmation before it applies the ceilings.
  -h, --help   This text.

Ceilings, in MB:

  UNDOTBS*      2048    AUDIT_TRAIL   1024    USERS      1024
  TBS_APEX      3072    TBS_*         2048    other      2048
  SYSTEM        never   SYSAUX        never

SYSTEM and SYSAUX are never capped. An ORA-01653 in the middle of a dictionary
operation is a worse failure than the disk it saves, and a full SYSAUX breaks the
scheduler and the AWR jobs in ways that are hard to read. Both grow slowly.

A file that is already larger than its target ceiling gets a ceiling at its
current size. Run `shrink-space` first, then run this script again to bring the
ceiling down to the target.

A ceiling that is already at or below the target is never raised, so a tighter
limit that you set by hand stays.

This reports the PDB only. The 12 GB limit that stops a PDB from opening is
measured per PDB, so that is the scope that matters.
USAGE
}

MODE="check"
AUTO_YES=false
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    --summary) MODE="summary" ;;
    -y | --yes) AUTO_YES=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ "$MODE" = "summary" ]; then
  source ./scripts/util/load_env.sh >/dev/null
else
  source ./scripts/util/load_env.sh
fi

# Every mode below reads this one inline view, so the report and the change can
# never disagree about what needs a ceiling.
#
# "Uncapped" is NOT `maxbytes = 0`. Measured on 23.26.2: maxbytes = 0 means
# autoextensible = 'NO', which is a file with a FIXED size -- already safe. An
# uncapped autoextensible file reports the architectural sentinel
# 35184372064256 (32 TB), and reports the same value for a smallfile and a
# bigfile tablespace, so there is no smallfile branch to write. Comparing against
# the 12 GB limit instead of against the sentinel keeps working if Oracle ever
# changes it: a ceiling above the whole-database limit is not a ceiling.
#
# target_mb is the ceiling policy. SYSTEM and SYSAUX resolve to null, which means
# "never give this one a ceiling".
#
# want_mb is the ceiling the file is supposed to end up with. It is never below
# the current size of the file, because a ceiling under the current size is
# rejected and would be pointless.
#
# pending = 'Y' marks a file whose ceiling is HIGHER than want_mb, which covers
# both cases that matter: no ceiling at all (the 32 TB sentinel is higher than
# anything), and a ceiling left too high after the file became smaller. A ceiling
# that is already at or below want_mb is never touched, so a tighter limit that
# somebody set by hand is never raised.
FILES_VIEW="select df.tablespace_name,
              df.file_name,
              df.autoextensible,
              ceil(df.bytes/1024/1024) cur_mb,
              round(df.maxbytes/1024/1024) max_mb,
              case when df.maxbytes > 12 * 1024 * 1024 * 1024
                   then 'none'
                   else to_char(round(df.maxbytes/1024/1024)) end ceiling,
              t.target_mb,
              greatest(t.target_mb, ceil(df.bytes/1024/1024)) want_mb,
              case when df.autoextensible = 'YES'
                    and t.target_mb is not null
                    and round(df.maxbytes/1024/1024) >
                        greatest(t.target_mb, ceil(df.bytes/1024/1024))
                   then 'Y' else 'N' end pending
         from dba_data_files df
         cross join lateral (
              select case
                       when df.tablespace_name in ('SYSTEM', 'SYSAUX') then null
                       when df.tablespace_name like 'UNDOTBS%'         then 2048
                       when df.tablespace_name = 'AUDIT_TRAIL'         then 1024
                       when df.tablespace_name = 'USERS'               then 1024
                       when df.tablespace_name = 'TBS_APEX'            then 3072
                       else 2048
                     end target_mb from dual) t"

if [ "$MODE" = "summary" ]; then
  if ! summary_out=$(sql -S -name "$DB_CONN_NAME" <<SQL
whenever sqlerror exit failure
set heading off feedback off pagesize 0
alter session set nls_numeric_characters = '.,';

select 'pdb_total_gb=' || round(sum(bytes)/1024/1024/1024, 2) from dba_data_files;
select 'pdb_limit_gb=12' from dual;

with f as ($FILES_VIEW)
select 'uncapped_files=' || count(*) from f
 where ceiling = 'none' and target_mb is not null;
with f as ($FILES_VIEW)
select 'uncapped_mb=' || nvl(sum(cur_mb), 0) from f
 where ceiling = 'none' and target_mb is not null;
with f as ($FILES_VIEW)
select 'pending_files=' || count(*) from f where pending = 'Y';
with f as ($FILES_VIEW)
select 'capped_files=' || count(*) from f
 where autoextensible = 'YES' and ceiling <> 'none';
with f as ($FILES_VIEW)
select 'fixed_files=' || count(*) from f where autoextensible = 'NO';

select 'undo_tablespace=' || value from v\$parameter where name = 'undo_tablespace';
select 'undo_retention=' || value from v\$parameter where name = 'undo_retention';
select 'undo_files=' || count(*) from dba_data_files where tablespace_name like 'UNDOTBS%';
with f as ($FILES_VIEW)
select 'undo_max_mb=' || min(ceiling) from f
 where tablespace_name like 'UNDOTBS%' and autoextensible = 'YES';
select 'undo_guarantee=' || min(retention) from dba_tablespaces where contents = 'UNDO';

select 'audit_mb=' || nvl(round(sum(bytes)/1024/1024), 0) from dba_data_files
 where tablespace_name = 'AUDIT_TRAIL';
with f as ($FILES_VIEW)
select 'audit_max_mb=' || min(ceiling) from f where tablespace_name = 'AUDIT_TRAIL';
select 'audit_purge_job=' ||
       case when count(*) > 0 then 'present' else 'absent' end
  from dba_scheduler_jobs where job_name = 'UC_AUDIT_PURGE';
exit
SQL
  ); then
    echo "cap-tablespaces: could not read the database space usage." >&2
    exit 1
  fi
  # SQLcl right-pads every column, so trim before calling this machine-readable
  printf '%s\n' "$summary_out" | sed 's/[[:space:]]*$//' | grep -v '^[[:space:]]*$'
  exit 0
fi

sql -name "$DB_CONN_NAME" <<SQL
alter session set nls_numeric_characters = '.,';
set lines 200 pages 200
col tablespace_name format a24
col file_name format a54
col state format a10

prompt
prompt Space against the 12GB Free-edition limit:
select round(sum(bytes)/1024/1024/1024, 2) current_gb,
       12 limit_gb,
       round(12 - sum(bytes)/1024/1024/1024, 2) headroom_gb
  from dba_data_files;

prompt
prompt Datafiles that need a ceiling change ("none" can grow until the PDB stops opening):
with f as ($FILES_VIEW)
select tablespace_name, cur_mb, ceiling, want_mb new_ceiling, file_name
  from f where pending = 'Y'
 order by cur_mb desc;

prompt
prompt Datafiles whose ceiling is already correct:
with f as ($FILES_VIEW)
select tablespace_name, cur_mb, ceiling,
       case when autoextensible = 'NO' then 'fixed'
            when target_mb is null     then 'by policy'
            else 'capped' end state
  from f where pending = 'N'
 order by cur_mb desc;

prompt
prompt Undo:
select df.tablespace_name,
       round(df.bytes/1024/1024) cur_mb,
       round(df.maxbytes/1024/1024) max_mb,
       df.autoextensible,
       ts.retention
  from dba_data_files df
  join dba_tablespaces ts on ts.tablespace_name = df.tablespace_name
 where df.tablespace_name like 'UNDOTBS%'
 order by df.tablespace_name;
SQL

# An undo tablespace that is not the active one is dead weight. Report it, and
# never act on it: dropping the wrong undo tablespace is unrecoverable.
idle_undo=$(sql -S -name "$DB_CONN_NAME" <<SQL
set heading off feedback off pagesize 0
select '###' || df.tablespace_name || ' (' || round(df.bytes/1024/1024) || 'M)'
  from dba_data_files df
 where df.tablespace_name like 'UNDOTBS%'
   and df.tablespace_name <> (select value from v\$parameter
                               where name = 'undo_tablespace');
exit
SQL
)
idle_undo=$(printf '%s' "$idle_undo" | grep -o '###.*' | sed 's/^###//;s/[[:space:]]*$//')

if [ -n "$idle_undo" ]; then
  echo ""
  echo "Note: $idle_undo is not the undo tablespace in use. It is dead weight, and"
  echo "      you can drop it to get that space back. This script never drops a"
  echo "      tablespace, because dropping the wrong undo tablespace cannot be undone."
fi

if [ "$MODE" = "check" ]; then
  echo ""
  echo "This was a read-only check. Run with --apply to set the ceilings."
  echo "Note: this reports the PDB only. The 12GB limit that stops a PDB from"
  echo "      opening is measured per PDB, so that is the scope that matters."
  exit 0
fi

echo ""
echo "This will set the new ceiling on every datafile listed above as pending."
echo "SYSTEM and SYSAUX are not changed. Nothing is dropped and no data moves."

if [ "$AUTO_YES" = true ]; then
  echo "Auto-confirmed with -y."
  answer="y"
elif [ -t 0 ]; then
  read -r -p "Continue? (y/n) " answer
else
  answer="y"
fi

if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
  echo "Stopping..."
  exit 0
fi

sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on size unlimited

declare
  l_n number := 0;
begin
  -- want_mb is never below the current size of the file, so this cannot truncate
  -- anything and cannot be rejected for being too small. A file that is still
  -- bigger than its policy target keeps a ceiling at its current size, and the
  -- message says what to do about that.
  for r in (with f as ($FILES_VIEW)
            select tablespace_name, file_name, cur_mb, target_mb, want_mb
              from f where pending = 'Y'
             order by cur_mb desc)
  loop
    begin
      execute immediate 'alter database datafile '''||r.file_name||
        ''' autoextend on next 32M maxsize '||r.want_mb||'M';
      l_n := l_n + 1;
      if r.want_mb > r.target_mb then
        dbms_output.put_line('capped '||rpad(r.tablespace_name, 24)||r.want_mb||
          'M -- above the '||r.target_mb||'M target, because the file is '||
          'already that big. Run shrink-space, then run this script again.');
      else
        dbms_output.put_line('capped '||rpad(r.tablespace_name, 24)||r.want_mb||'M');
      end if;
    exception when others then
      dbms_output.put_line('skip   '||rpad(r.tablespace_name, 24)||sqlerrm);
    end;
  end loop;
  dbms_output.put_line('');
  dbms_output.put_line('changed '||l_n||' datafile ceiling(s)');
end;
/
SQL

echo ""
echo "Done. Run 'cap-tablespaces --check' again to make sure that nothing is pending."
echo "If a file kept a ceiling above its target, run 'shrink-space' and repeat."
