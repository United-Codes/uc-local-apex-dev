#!/usr/bin/env bash
# desc: Import every export file found in ./backups/import (-y skips the prompt, -j N runs N DataPump jobs at once)

set -e

source ./scripts/util/load_env.sh

ASSUME_YES=false
JOBS=1
while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes)
      ASSUME_YES=true
      shift
      ;;
    -j | --jobs)
      if ! [[ "${2:-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: -j needs a positive number"
        exit 1
      fi
      JOBS="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [-y] [-j <jobs>]"
      exit 1
      ;;
  esac
done

source ./scripts/util/read_user_names.sh
source ./scripts/util/manifest.sh

# The backup lists the schemas it found in recovery/schemas.tsv. That includes
# schemas that are not in .env. A backup of an older release has no such file.
RECOVERY_DIR="./backups/import/recovery"
USERNAMES=()
if [ -s "$RECOVERY_DIR/schemas.tsv" ]; then
  while IFS='|' read -r name _; do
    [ -n "$name" ] && USERNAMES+=("$name")
  done <"$RECOVERY_DIR/schemas.tsv"
else
  read -r -a USERNAMES <<<"$(get_user_names)"
fi

if [ ${#USERNAMES[@]} -eq 0 ]; then
  echo "No user password entries found in .env file"
  exit 0
fi

echo "Found ${#USERNAMES[@]} users to import:"
for user in "${USERNAMES[@]}"; do
  echo "  - $user"
done

if [ "$ASSUME_YES" = false ]; then
  echo ""
  read -r -p "Do you want to import all these users? (y/n) " answer

  if [[ $answer != "y" ]] && [[ $answer != "Y" ]]; then
    echo "Stopping..."
    exit 0
  fi
fi

echo ""
echo "Starting import process..."
echo ""

SUCCESSFUL=0
FAILED=0
FAILED_USERS=()

LOG_DIR="./backups/import/logs"
STATUS_DIR=$(mktemp -d)
mkdir -p "$LOG_DIR"

# Imported jobs and automations must not run while the import is running. Switch
# the scheduler off, and put the old value back at the end, also after a failure.
OLD_JQP=$(sql -S -name "$DB_CONN_NAME" <<'SQL' 2>/dev/null | grep -Eo '^[0-9]+' | head -n1
set heading off feedback off pagesize 0
select value from v$parameter where name = 'job_queue_processes';
exit;
SQL
)
restore_jobs() {
  rm -rf "$STATUS_DIR"
  if [ -n "${OLD_JQP:-}" ]; then
    sql -S -name "$DB_CONN_NAME" >/dev/null 2>&1 <<SQL || true
alter system set job_queue_processes = $OLD_JQP;
exit;
SQL
  fi
}
trap restore_jobs EXIT
if [ -n "${OLD_JQP:-}" ] && [ "$OLD_JQP" != "0" ]; then
  sql -S -name "$DB_CONN_NAME" >/dev/null 2>&1 <<'SQL' || true
alter system set job_queue_processes = 0;
exit;
SQL
  echo "Scheduler jobs are off during the import (job_queue_processes was $OLD_JQP)."
fi

run_sql_file() {
  local file="$1" log="$2"
  sql -S -name "$DB_CONN_NAME" <<SQL >"$log" 2>&1 || true
set define off
@$file
exit;
SQL
  # One marker per failed statement: "Error report -" (SQL) or "ERROR at line" (PL/SQL).
  echo "  $(basename "$file"): $(grep -cE '^(Error report -|ERROR at line)' "$log" || true) statements failed. See $log"
}

# Phases. Only the DataPump phase of different schemas is independent, so only
# that phase runs in parallel. The Free edition has 2 CPUs, so more than 2 jobs
# does not help.
#   0. pre      SQL as SYS: profiles, tablespaces, roles, directories, discovered users
#   1. create   serial: create-user.sh edits the SQLcl connection store and the shared ACL
#   2. DataPump parallel with -j, one log file per schema. Every user exists first,
#               so a grant to another schema does not fail
#   3. APEX     serial: workspaces can share one id
#   4. ORDS     serial: short, and needs the APEX workspace
#   5. post     SQL as SYS: grants, synonyms, network entries, contexts, policies
if [ "$JOBS" -gt 2 ]; then
  echo "Note: the Free edition has 2 CPUs. More than 2 jobs does not make the import faster."
fi

mark_failed() { : >"$STATUS_DIR/$1.failed"; }

# Settings and components that the old database had (recovery/params.tsv).
param_value() { grep -E "^$1\|" "$RECOVERY_DIR/params.tsv" 2>/dev/null | head -n1 | cut -d'|' -f2 | tr -d '\r '; }
db_value() {
  sql -S -name "$DB_CONN_NAME" <<SQL 2>/dev/null | tr -d '\r ' | grep -Ev '^$' | tail -n1
set heading off feedback off pagesize 0
$1
exit;
SQL
}

# A vector index (HNSW) needs vector memory, or DataPump skips it with ORA-51962.
# The size of the container database can only grow with a restart.
WANT_VMEM=$(param_value vector_memory_size)
if [ -n "$WANT_VMEM" ]; then
  HAVE_VMEM=$(db_value "select value from v\$parameter where name = 'vector_memory_size';")
  if [ "${HAVE_VMEM:-0}" -lt "$WANT_VMEM" ] 2>/dev/null; then
    echo "== Phase 0: vector memory $WANT_VMEM bytes (the old database had it). The database restarts."
    # shellcheck disable=SC2016
    $CONTAINER_CLI exec -i "${CONTAINER_NAME:-local-26ai}" bash -c 'source /home/oracle/.bashrc 2>/dev/null; $ORACLE_HOME/bin/sqlplus -S / as sysdba' >"$LOG_DIR/vector_memory.log" 2>&1 <<SQL
alter system set vector_memory_size = $WANT_VMEM scope = spfile;
shutdown immediate
startup
alter pluggable database all open;
alter session set container = FREEPDB1;
alter system set vector_memory_size = $WANT_VMEM scope = both;
exit
SQL
    HAVE_VMEM=$(db_value "select value from v\$parameter where name = 'vector_memory_size';")
    if [ "${HAVE_VMEM:-0}" -lt "$WANT_VMEM" ] 2>/dev/null; then
      echo "  ✗ could not set the vector memory. See $LOG_DIR/vector_memory.log. Vector indexes can fail."
    fi
  fi
fi

# Components that the old database had and this one does not have yet.
if [ "$(param_value dbms_cloud)" = "installed" ] &&
  [ "$(db_value "select count(*) from dba_users where username = 'C##CLOUD\$SERVICE';")" = "0" ]; then
  echo "Note: the old database had DBMS_CLOUD. Grants on it fail. Run ./local-26ai.sh install-dbms-cloud, then run recovery/10_post.sql again."
fi
if [ "$(param_value utplsql)" = "installed" ] &&
  [ "$(db_value "select count(*) from dba_users where username = 'UTPLSQL';")" = "0" ]; then
  echo "Note: the old database had utPLSQL. Run ./local-26ai.sh install-utplsql."
fi

if [ -f "$RECOVERY_DIR/00_pre.sql" ]; then
  echo "== Phase 0: 00_pre.sql (profiles, tablespaces, roles, directories, scheduler windows, discovered users)"
  run_sql_file "$RECOVERY_DIR/00_pre.sql" "$LOG_DIR/00_pre.log"
fi

# The paths of the directories, and the files that the backup copied from them.
DIR_FAILURES=0
if [ -s "$RECOVERY_DIR/dirs.tsv" ]; then
  echo "== Phase 0: directory paths and files"
  CONTAINER="${CONTAINER_NAME:-local-26ai}"
  while IFS='|' read -r name path; do
    path="${path%$'\r'}"
    path="${path%"${path##*[![:space:]]}"}"
    [ -z "$name" ] && continue
    if ! $CONTAINER_CLI exec "$CONTAINER" mkdir -p "$path" </dev/null; then
      echo "  ✗ cannot create $path for directory $name"
      DIR_FAILURES=$((DIR_FAILURES + 1))
    elif [ -s "$RECOVERY_DIR/dirfiles/$name.tar" ]; then
      if $CONTAINER_CLI exec -i "$CONTAINER" tar -C "$path" -xf - <"$RECOVERY_DIR/dirfiles/$name.tar"; then
        echo "  restored the files of directory $name ($path)"
      else
        echo "  ✗ cannot restore the files of directory $name into $path"
        DIR_FAILURES=$((DIR_FAILURES + 1))
      fi
    else
      echo "  created $path for directory $name"
    fi
  done <"$RECOVERY_DIR/dirs.tsv"
fi

echo "== Phase 1: create users"
for USERNAME in "${USERNAMES[@]}"; do
  ./scripts/import-backup.sh "$USERNAME" -y --only create >"$LOG_DIR/$USERNAME.create.log" 2>&1 ||
    { echo "✗ create failed for $USERNAME (see $LOG_DIR/$USERNAME.create.log)"; mark_failed "$USERNAME"; }
done

# SQL domains whose DataPump DDL is broken. They must exist before the tables.
if [ -s "$RECOVERY_DIR/05_domains.sql" ] && grep -qi 'create' "$RECOVERY_DIR/05_domains.sql"; then
  echo "== Phase 1: 05_domains.sql (SQL domains with corrected DDL)"
  run_sql_file "$RECOVERY_DIR/05_domains.sql" "$LOG_DIR/05_domains.log"
fi

echo "== Phase 2: DataPump with $JOBS parallel job(s)"
PAR_USERS=()
for USERNAME in "${USERNAMES[@]}"; do
  [ -f "$STATUS_DIR/$USERNAME.failed" ] || PAR_USERS+=("$USERNAME")
done
# The child script is single-quoted on purpose: $1 is for the child, not for us.
# shellcheck disable=SC2016
[ ${#PAR_USERS[@]} -gt 0 ] && printf '%s\n' "${PAR_USERS[@]}" | STATUS_DIR="$STATUS_DIR" LOG_DIR="$LOG_DIR" xargs -P "$JOBS" -I{} bash -c '
  if ./scripts/import-backup.sh "$1" -y --only data >"$LOG_DIR/$1.data.log" 2>&1; then
    echo "✓ data imported for $1"
  else
    echo "✗ data import failed for $1 (see $LOG_DIR/$1.data.log)"
    : >"$STATUS_DIR/$1.failed"
  fi
' _ {} || true

for phase in apex ords; do
  echo "== Phase: $phase"
  for USERNAME in "${USERNAMES[@]}"; do
    [ -f "$STATUS_DIR/$USERNAME.failed" ] && continue
    ./scripts/import-backup.sh "$USERNAME" -y --only "$phase" >"$LOG_DIR/$USERNAME.$phase.log" 2>&1 ||
      { echo "✗ $phase failed for $USERNAME (see $LOG_DIR/$USERNAME.$phase.log)"; mark_failed "$USERNAME"; }
  done
done

# Roles, grants, public synonyms and more that a schema export does not carry.
# They run also if a schema failed: the schemas that worked need their grants.
if [ -f "$RECOVERY_DIR/10_post.sql" ]; then
  echo "== Phase 5: 10_post.sql (grants, synonyms, network entries, contexts, policies)"
  run_sql_file "$RECOVERY_DIR/10_post.sql" "$LOG_DIR/10_post.log"
elif [ -f "$RECOVERY_DIR/recover.sql" ]; then
  echo "== Phase 5: recover.sql (backup of an older release)"
  run_sql_file "$RECOVERY_DIR/recover.sql" "$LOG_DIR/recover.log"
else
  echo "Note: no recovery files in $RECOVERY_DIR. Roles, grants and public synonyms are not restored."
  echo "      Copy ./backups/export/recovery to ./backups/import/recovery to restore them."
fi

# Compare the object counts with the backup. This finds objects that no step
# reported as failed, for example a queue or an index that DataPump skipped.
MANIFEST_DIFFS=""
if [ -s "$RECOVERY_DIR/manifest.tsv" ]; then
  echo "== Check: objects against the backup"
  if MANIFEST_DIFFS=$(compare_manifest "$RECOVERY_DIR/manifest.tsv"); then
    echo "  every object of the backup is in the database"
  else
    echo "  WARNING: these objects did not come back:"
    while IFS= read -r line; do echo "    $line"; done <<<"$MANIFEST_DIFFS"
  fi
fi

for USERNAME in "${USERNAMES[@]}"; do
  if [ -f "$STATUS_DIR/$USERNAME.failed" ]; then
    FAILED=$((FAILED + 1))
    FAILED_USERS+=("$USERNAME")
  else
    SUCCESSFUL=$((SUCCESSFUL + 1))
  fi
done

echo "========================================"
echo "Import Summary"
echo "========================================"
echo "Total users: ${#USERNAMES[@]}"
echo "Successfully imported: $SUCCESSFUL"
echo "Failed: $FAILED"

if [ -n "$MANIFEST_DIFFS" ]; then
  FAILED=$((FAILED + 1))
  FAILED_USERS+=("(objects of the backup are missing, see above)")
fi
if [ "$DIR_FAILURES" -gt 0 ]; then
  FAILED=$((FAILED + 1))
  FAILED_USERS+=("(directory files, see Phase 0 above)")
fi

if [ $FAILED -gt 0 ]; then
  echo ""
  echo "Failed users:"
  for user in "${FAILED_USERS[@]}"; do
    echo "  - $user"
  done
  exit 1
fi

echo ""
echo "All users imported successfully!"

# Things that no backup holds. Show them last, so that nobody misses them.
if [ -f "$RECOVERY_DIR/unrecoverable.txt" ] && grep -q '[^[:space:]]' "$RECOVERY_DIR/unrecoverable.txt"; then
  echo ""
  echo "No backup holds these. Enter or create them again:"
  grep -v '^[[:space:]]*$' "$RECOVERY_DIR/unrecoverable.txt" | sed 's/^/  - /'
fi
