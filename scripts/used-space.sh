#!/usr/bin/env bash
# desc: Show database space usage vs the 12GB Free-edition limit (--summary, --quiet)

set -e

# The Free edition allows 12 GB of datafiles per PDB. A PDB that goes over the
# limit will not open again in ANY mode: ORA-12954 is raised before the open, so
# "open read only" and "open upgrade" fail identically and nothing inside the PDB
# can be changed to repair it. Recovery needs manual surgery with the CDB in
# MOUNT state. So this script is also the early-warning device, and it reports
# its verdict through the exit code:
#
#   0   OK
#   1   the script itself failed (cannot connect, unknown option)
#   10  WARNING   -- total >= SPACE_WARN_GB
#   11  CRITICAL  -- total >= SPACE_CRIT_GB
#
# 10 and 11 rather than 2 and 3 so a caller can tell "the check ran and the news
# is bad" apart from "the check broke".

usage() {
  cat <<'USAGE'
Usage: scripts/used-space.sh [options]

  --summary   Machine-readable "key=value" lines only. Read-only.
  --quiet     Print nothing. Use the exit code. Read-only.
  -h, --help  This text.

With no option, show the full per-tablespace report.

Exit codes: 0 OK, 1 script failure, 10 WARNING, 11 CRITICAL.
Thresholds come from SPACE_WARN_GB (default 9.5) and SPACE_CRIT_GB (default 11)
in .env.
USAGE
}

MODE="report"
while [ $# -gt 0 ]; do
  case "$1" in
    --summary) MODE="summary" ;;
    --quiet) MODE="quiet" ;;
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

if [ "$MODE" = "report" ]; then
  source ./scripts/util/load_env.sh
else
  # load_env.sh echoes "loaded .env file"; keep the machine-readable modes clean
  source ./scripts/util/load_env.sh >/dev/null
fi

# The warning threshold sits well below the limit on purpose. Every way out of a
# full database needs room to work: dbms_space.shrink_tablespace needs undo,
# compress-space rebuilds need TEMP plus a second copy of the segment, and a
# rescue export needs somewhere to write the dumpfile. At 11 GB none of that is
# available and only the manual recovery is left.
WARN_GB="${SPACE_WARN_GB:-9.5}"
CRIT_GB="${SPACE_CRIT_GB:-11}"

# The full report also lists the largest segments of every tablespace that uses
# at least this much space. Only the full report shows it.
DETAIL_MIN_MB=1024
DETAIL_TOP_N=10

# Read the numbers first, in one quiet call, so the status is decided in SQL.
# bash 3.2 (the macOS default) cannot compare floats, so it must not try.
# The ### sentinel strips the SQLcl banner -- same idiom as user-exists-in-db.sh.
if ! raw=$(sql -S -name "$DB_CONN_NAME" <<SQL
whenever sqlerror exit failure
set heading off feedback off pagesize 0
-- a comma decimal separator would break every caller that parses these numbers
alter session set nls_numeric_characters = '.,';
select '###current_gb=' || round(sum(bytes)/1024/1024/1024, 2) ||
       '|pct=' || round(sum(bytes)/1024/1024/1024/12*100, 1) ||
       '|status=' ||
       case
         when sum(bytes)/1024/1024/1024 >= $CRIT_GB then 'CRITICAL'
         when sum(bytes)/1024/1024/1024 >= $WARN_GB then 'WARNING'
         else 'OK'
       end
  from dba_data_files;
exit
SQL
); then
  echo "used-space: could not read the database space usage." >&2
  exit 1
fi

line=$(printf '%s' "$raw" | grep -o '###[^ ]*' | head -n1 | sed 's/^###//')
if [ -z "$line" ]; then
  echo "used-space: could not read the database space usage." >&2
  exit 1
fi

CURRENT_GB=$(printf '%s' "$line" | sed -n 's/.*current_gb=\([^|]*\).*/\1/p')
PCT=$(printf '%s' "$line" | sed -n 's/.*pct=\([^|]*\).*/\1/p')
STATUS=$(printf '%s' "$line" | sed -n 's/.*status=\([^|]*\).*/\1/p')

case "$STATUS" in
  CRITICAL) RC=11 ;;
  WARNING) RC=10 ;;
  *) RC=0 ;;
esac

if [ "$MODE" = "summary" ]; then
  echo "current_gb=$CURRENT_GB"
  echo "limit_gb=12"
  echo "pct_of_limit=$PCT"
  echo "warn_gb=$WARN_GB"
  echo "crit_gb=$CRIT_GB"
  echo "status=$STATUS"
  exit $RC
fi

if [ "$MODE" = "quiet" ]; then
  exit $RC
fi

sql -name "$DB_CONN_NAME" <<SQL
-- show 9.94 rather than 9,94, matching the sample output in the documentation
alter session set nls_numeric_characters = '.,';

SELECT
    ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS current_gb,
    12 AS limit_gb,
    ROUND((SUM(bytes) / 1024 / 1024 / 1024 / 12) * 100, 2) AS percent_of_limit,
    CASE
        WHEN SUM(bytes) / 1024 / 1024 / 1024 >= $CRIT_GB THEN 'CRITICAL'
        WHEN SUM(bytes) / 1024 / 1024 / 1024 >= $WARN_GB THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM dba_data_files
;

  select df.tablespace_name "Tablespace",
       df.totalspace "Total MB",
       totalusedspace "Used MB",
       (df.totalspace - tu.totalusedspace) "Free MB",
       round(100 * ( (df.totalspace - tu.totalusedspace)/ df.totalspace)) "Pct. Free"
  from (select tablespace_name,
               round(sum(bytes) / 1048576) TotalSpace
          from dba_data_files
         group by tablespace_name) df,
       (select round(sum(bytes)/(1024*1024)) totalusedspace,
               tablespace_name
          from dba_segments
         group by tablespace_name) tu
 where df.tablespace_name = tu.tablespace_name
 order by totalspace desc;

-- Detail for the big tablespaces: the largest segments in each one. A tablespace
-- is big when its segments use DETAIL_MIN_MB or more. LOB segments and indexes
-- show the table they belong to, because their system names tell nothing.
prompt
prompt Largest segments in tablespaces with $DETAIL_MIN_MB MB or more used:

column "Tablespace" format a20
column "Owner" format a24
column "Segment" format a50
column "Type" format a16
column "Size MB" format 999,999,990
column "Pct. of TS" format 990.0

with ts as (
  select tablespace_name, sum(bytes) ts_bytes
    from dba_segments
   group by tablespace_name
  having sum(bytes) >= $DETAIL_MIN_MB * 1048576
),
ranked as (
  select s.tablespace_name, s.owner, s.segment_name, s.segment_type, s.bytes,
         ts.ts_bytes,
         row_number() over (partition by s.tablespace_name
                            order by s.bytes desc) rn
    from dba_segments s
    join ts on ts.tablespace_name = s.tablespace_name
)
select r.tablespace_name "Tablespace",
       r.owner "Owner",
       case
         when l.table_name is not null
           then l.table_name || '.' || l.column_name || ' (LOB)'
         when i.table_name is not null
           then r.segment_name || ' (on ' || i.table_name || ')'
         else r.segment_name
       end "Segment",
       r.segment_type "Type",
       round(r.bytes / 1048576) "Size MB",
       round(100 * r.bytes / r.ts_bytes, 1) "Pct. of TS"
  from ranked r
  left join dba_lobs l
    on r.segment_type like 'LOB%'
   and l.owner = r.owner
   and (l.segment_name = r.segment_name or l.index_name = r.segment_name)
  left join dba_indexes i
    on r.segment_type like 'INDEX%'
   and i.owner = r.owner
   and i.index_name = r.segment_name
 where r.rn <= $DETAIL_TOP_N
 order by r.ts_bytes desc, r.tablespace_name, r.bytes desc;

-- APEX stores application files in a few shared tables, so the segment list above
-- cannot say which application owns the space. This adds the owner. The sizes are
-- the length of the file content. The segment is larger, because LOB storage has
-- overhead and keeps the space of deleted files until a shrink.
prompt
prompt APEX file content per application (top $DETAIL_TOP_N):

column "Workspace" format a20
column "App" format 999999
column "Application" format a50
column "Content" format a22
column "Files" format 999,990

with f as (
  select 'Application files' kind, flow_id app_id, security_group_id sgid,
         dbms_lob.getlength(blob_content) len
    from flows_files.wwv_flow_file_objects\$
  union all
  select 'Static files', application_id, null, dbms_lob.getlength(file_content)
    from apex_application_static_files
  union all
  select 'Plug-in files', application_id, null, dbms_lob.getlength(file_content)
    from apex_appl_plugin_files
)
select nvl(a.workspace, 'security group ' || f.sgid) "Workspace",
       f.app_id "App",
       substr(a.application_name, 1, 50) "Application",
       f.kind "Content",
       count(*) "Files",
       round(sum(f.len) / 1048576, 1) "Size MB"
  from f
  left join apex_applications a on a.application_id = f.app_id
 group by a.workspace, f.sgid, f.app_id, a.application_name, f.kind
 order by sum(f.len) desc nulls last
 fetch first $DETAIL_TOP_N rows only;
SQL

echo "Run the shrink-space script to reclaim unused space across all tablespaces."
echo "To also make a single schema's data smaller, run: compress-space <schema>"
echo "To stop one file from growing without a limit, run: cap-tablespaces --check"

exit $RC
