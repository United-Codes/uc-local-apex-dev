#!/usr/bin/env bash
# desc: Restore a schema from a previous backup (creates the user if missing)

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user_in_env.sh
source ./scripts/util/user-exists-in-db.sh
source ./scripts/util/schema-access.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name> [-rs <remap_schema_name>] [-rt <old_tbs>=<new_tbs>[,...]] [-y] [--only create|data|apex|ords]"
  exit 1
fi
USERNAME=$1
USERNAME_UPPER=$(echo "$USERNAME" | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

# Parse optional parameters
# An array, so that each flag and its value reach import-datapump.sh as separate
# arguments. A single quoted string arrived as one word and the remap was lost.
REMAP_ARGS=()
SKIP_CONFIRMATION=false
# --only runs one phase. import-all uses it to run the data phase of several
# schemas in parallel and every other phase one after the other.
ONLY=""
shift # Remove first argument (USERNAME)

while [[ $# -gt 0 ]]; do
  case $1 in
    -rs)
      if [ -n "$2" ]; then
        REMAP_ARGS+=(-rs "$2")
        shift 2
      else
        echo "Error: -rs requires a schema name"
        exit 1
      fi
      ;;
    -rt)
      if [ -n "$2" ]; then
        REMAP_ARGS+=(-rt "$2")
        shift 2
      else
        echo "Error: -rt requires <old_tbs>=<new_tbs>"
        exit 1
      fi
      ;;
    --only)
      case "${2:-}" in
        create | data | apex | ords)
          ONLY="$2"
          shift 2
          ;;
        *)
          echo "Error: --only needs create, data, apex or ords"
          exit 1
          ;;
      esac
      ;;
    -y)
      SKIP_CONFIRMATION=true
      shift
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

# A schema that the backup found in the database, and that .env does not know
# (recovery/schemas.tsv says "discovered"). 00_pre.sql made the user, with the
# old password hash. The owner steps (DataPump, ORDS) need a SQLcl connection, so
# the owner gets a temporary password. schema-access.sh puts the hash back.
DISCOVERED=false
if grep -qx "${USERNAME_UPPER}|discovered" ./backups/import/recovery/schemas.tsv 2>/dev/null &&
  ! user_in_env_bool "$USERNAME_UPPER"; then
  DISCOVERED=true
fi
APEX_LOG=""
cleanup_import() {
  [ -n "$APEX_LOG" ] && rm -f "$APEX_LOG"
  if [ "${DISCOVERED_NEEDS_ACCESS:-false}" = true ] && want ords; then schema_access_end "$USERNAME_UPPER"; fi
  return 0
}
trap cleanup_import EXIT
# Only the ORDS step needs the owner. Without an ORDS export there is nothing to do.
if [ "$DISCOVERED" = true ] && want ords && [ ! -f "./backups/import/ords/$USERNAME_LOWER/rest_schema.sql" ]; then
  DISCOVERED_NEEDS_ACCESS=false
else
  DISCOVERED_NEEDS_ACCESS=$DISCOVERED
fi
if [ "$DISCOVERED_NEEDS_ACCESS" = true ] && want ords; then
  if ! user_exists_in_db "$USERNAME_UPPER"; then
    echo "Error: $USERNAME_UPPER is a discovered schema, but 00_pre.sql did not create it." >&2
    echo "       Run ./backups/import/recovery/00_pre.sql as SYS first." >&2
    exit 1
  fi
  schema_access_begin "$USERNAME_UPPER"
fi

# Check if we have an APEX workspace file to import later
APEX_DIR="./backups/import/apex/$USERNAME_LOWER"
HAS_WORKSPACE_FILE=false
if [ -d "$APEX_DIR" ]; then
  WORKSPACE_FILE=$(find "$APEX_DIR" -maxdepth 1 -name "w[0-9]*.sql" -type f | head -n 1)
  if [ -n "$WORKSPACE_FILE" ]; then
    HAS_WORKSPACE_FILE=true
    echo "Found APEX workspace file to import: $(basename "$WORKSPACE_FILE")"
  fi
fi

if want create && [ "$DISCOVERED" = true ]; then
  echo "$USERNAME_UPPER is a discovered schema. 00_pre.sql made the user."
elif want create; then
  # if user exists in .env file
  if user_in_env_bool "$USERNAME_UPPER"; then
    # check if user is in the database
    if user_exists_in_db "$USERNAME_UPPER"; then
      echo "User $USERNAME_UPPER exists in the database"

      if [ "$SKIP_CONFIRMATION" = false ]; then
        read -r -p "Overwriting $USERNAME_UPPER with import. Do you want to continue? (y/n) " answer

        if [[ $answer == "y" ]] || [[ $answer == "Y" ]]; then
          echo "Continuing..."
        else
          echo "Stopping..."
          exit 0
        fi
      else
        echo "Overwriting $USERNAME_UPPER with import (confirmation skipped with -y)"
      fi
    else
      echo "User $USERNAME_UPPER does not exist in the database"
      echo "Creating new user $USERNAME_UPPER"

      # scripts checks if user exists in the .env file
      if [ "$HAS_WORKSPACE_FILE" = true ]; then
        ./scripts/create-user.sh "$USERNAME_UPPER" --skip-workspace
      else
        ./scripts/create-user.sh "$USERNAME_UPPER"
      fi
    fi
  else
    echo "User $USERNAME_UPPER does not exist in the .env file"
    echo "Creating new user $USERNAME_UPPER"

    if [ "$HAS_WORKSPACE_FILE" = true ]; then
      ./scripts/create-user.sh "$USERNAME_UPPER" --skip-workspace
    else
      ./scripts/create-user.sh "$USERNAME_UPPER"
    fi
  fi
fi

if want data; then
  echo "Importing $USERNAME_UPPER"

  # check if .dmp file exists in backups/import
  if [ -f ./backups/import/"$USERNAME_LOWER".dmp ]; then
    # Push only this schema's dump. The whole-tree copy was slow, and it is not
    # safe while other imports run.
    ./scripts/sync-backups-folder.sh push "$USERNAME_LOWER"
    echo "Importing datapump from ./backups/import/$USERNAME_LOWER.dmp"
    ./scripts/import-datapump.sh "$USERNAME_UPPER" "${REMAP_ARGS[@]}"
  else
    echo "No .dmp file found at ./backups/import/$USERNAME_LOWER.dmp"
  fi
fi

USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

# Handle APEX workspace and apps
APEX_DIR="./backups/import/apex/$USERNAME_LOWER"
if want apex && [ -d "$APEX_DIR" ]; then
  echo "Found APEX directory: $APEX_DIR"

  # Find workspace file (w[0-9]+.sql)
  WORKSPACE_FILE=$(find "$APEX_DIR" -maxdepth 1 -name "w[0-9]*.sql" -type f | head -n 1)

  # Find app files (f[0-9]+.sql)
  APP_FILES=$(find "$APEX_DIR" -maxdepth 1 -name "f[0-9]*.sql" -type f | sort)

  if [ -n "$APP_FILES" ] && [ -z "$WORKSPACE_FILE" ]; then
    echo "ERROR: Found APEX app files but no workspace file (w*.sql) in $APEX_DIR"
    echo "APEX apps require a workspace to be imported first"
    exit 1
  fi

  # Import the workspace first, then the apps. One SQLcl session per file: the
  # first error ends a session, so a shared session would skip every app after
  # the failed one.
  #
  # An app can subscribe to a master app in the same workspace. If the master
  # is not in the database yet, the import fails with ORA-20987. The file order
  # (sorted by name) does not know the masters. So an app that fails goes to the
  # next pass, after the other apps. The passes stop when no app succeeds any more.
  #
  # Some subscriptions point to a master component that no export carries. One
  # example is a theme style of the Universal Theme that an upgraded APEX still
  # has and a new APEX install does not. Another is a plug-in of a master app
  # that is in no backup. Only a missing master of this kind is
  # handled, and only after the passes above: the app is imported from a
  # temporary copy that has the subscription removed. The script says so.
  APEX_LOG=$(mktemp)

  import_apex_file() {
    local rc
    sql -name "$DB_CONN_NAME" <<SQL 2>&1 | tee "$APEX_LOG"
@$1
exit;
SQL
    rc=${PIPESTATUS[0]}
    # A failed import ends the session with ORA-20987 and a non-zero exit code.
    [ "$rc" -eq 0 ] && ! grep -q '^ORA-20987' "$APEX_LOG"
  }

  # The error names one missing master at a time, so remove them one by one
  # until the import works or no new master is named.
  import_without_missing_subscriptions() {
    local file="$1" ids id tmp removed=" "
    tmp=$(mktemp "${TMPDIR:-/tmp}/apexapp.XXXXXX")
    cp "$file" "$tmp"
    while :; do
      ids=$(grep -Eo '(Static ID|APEXlang Name) "[0-9]+" can not be found' "$APEX_LOG" | grep -Eo '[0-9]{6,}' | sort -u)
      [ -n "$ids" ] || break
      for id in $ids; do
        case "$removed" in *" $id "*) break 2 ;; esac
        removed="$removed$id "
        echo "WARNING: $(basename "$file"): removing the subscription to the missing master component $id"
        perl -pi -e "s/wwv_imp_util\.get_subscription_id\($id,[^()]*(\([^()]*\))?[^()]*\)/null/g" "$tmp"
      done
      if import_apex_file "$tmp"; then
        rm -f "$tmp"
        return 0
      fi
    done
    rm -f "$tmp"
    return 1
  }

  if [ -n "$WORKSPACE_FILE" ]; then
    # The workspace file fails with ORA-20987 if the workspace exists already.
    # That is the case when you import a schema a second time. Skip it then.
    WS_ID=$(basename "$WORKSPACE_FILE" .sql)
    WS_ID=${WS_ID#w}
    WS_EXISTS=$(
      sql -S -name "$DB_CONN_NAME" <<SQL 2>/dev/null | grep -Eo '[0-9]+' | head -n1
set heading off feedback off pagesize 0 verify off
select count(*) from apex_workspaces where workspace_id = $WS_ID;
exit;
SQL
    )
    if [ "${WS_EXISTS:-0}" -gt 0 ]; then
      echo "APEX workspace $WS_ID exists already. Skipping the workspace import."
    else
      echo "Importing APEX workspace from $(basename "$WORKSPACE_FILE") as SYS user"
      import_apex_file "$WORKSPACE_FILE"
      echo "APEX workspace import completed"
    fi
  fi

  PENDING_APPS=$APP_FILES
  PASS=1
  while [ -n "$PENDING_APPS" ]; do
    FAILED_APPS=""
    for APP_FILE in $PENDING_APPS; do
      echo "Importing $(basename "$APP_FILE") as SYS user (pass $PASS)"
      if ! import_apex_file "$APP_FILE"; then
        FAILED_APPS="${FAILED_APPS:+$FAILED_APPS
}$APP_FILE"
      fi
    done
    if [ "$FAILED_APPS" = "$PENDING_APPS" ]; then
      # No app succeeded in this pass. Try the fallback for every failed app.
      STILL_FAILED=""
      for APP_FILE in $FAILED_APPS; do
        import_apex_file "$APP_FILE" >/dev/null 2>&1 || true
        if ! import_without_missing_subscriptions "$APP_FILE"; then
          STILL_FAILED="${STILL_FAILED:+$STILL_FAILED
}$APP_FILE"
        fi
      done
      if [ -n "$STILL_FAILED" ]; then
        echo "ERROR: these APEX applications failed to import:"
        while IFS= read -r line; do echo "  $line"; done <<<"$STILL_FAILED"
        exit 1
      fi
      break
    fi
    if [ -n "$FAILED_APPS" ]; then
      echo "Retrying the applications that failed. A master application may be in the database now."
    fi
    PENDING_APPS=$FAILED_APPS
    PASS=$((PASS + 1))
  done
  echo "APEX applications import completed"
elif want apex; then
  echo "No APEX directory found at $APEX_DIR"
fi

# Handle ORDS REST schema
ORDS_DIR="./backups/import/ords/$USERNAME_LOWER"
REST_SCHEMA_FILE="$ORDS_DIR/rest_schema.sql"
if want ords && [ -f "$REST_SCHEMA_FILE" ]; then
  echo "Importing ORDS REST schema from $REST_SCHEMA_FILE as $USERNAME_UPPER user"
  # `rest export schema` writes one PL/SQL block and does NOT end it with a "/"
  # line. SQLcl then never runs the block, and the import does nothing without
  # an error. Run a copy that ends with "/".
  ORDS_RUN_FILE=$(mktemp "${TMPDIR:-/tmp}/ords_rest.XXXXXX")
  cat "$REST_SCHEMA_FILE" >"$ORDS_RUN_FILE"
  if [ "$(grep -v '^[[:space:]]*$' "$REST_SCHEMA_FILE" | tail -n 1 | tr -d '[:space:]')" != "/" ]; then
    printf '\n/\n' >>"$ORDS_RUN_FILE"
  fi
  sql -name "$USER_DB_CONN_NAME" <<SQL
@$ORDS_RUN_FILE
exit;
SQL
  rm -f "$ORDS_RUN_FILE"
  echo "ORDS REST schema import completed"
elif want ords; then
  echo "No ORDS REST schema file found at $REST_SCHEMA_FILE"
fi
