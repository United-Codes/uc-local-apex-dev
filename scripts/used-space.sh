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
SQL

echo "Run the shrink-space script to reclaim unused space across all tablespaces."
echo "To also make a single schema's data smaller, run: compress-space <schema>"
echo "To stop one file from growing without a limit, run: cap-tablespaces --check"

exit $RC
