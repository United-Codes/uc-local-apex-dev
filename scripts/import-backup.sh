#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user_in_env.sh
source ./scripts/util/user-exists-in-db.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name> [-rs <remap_schema_name>] [-y]"
  exit 1
fi
USERNAME=$1
USERNAME_UPPER=$(echo "$USERNAME" | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

# Parse optional parameters
REMAP_ARGS=""
SKIP_CONFIRMATION=false
shift # Remove first argument (USERNAME)

while [[ $# -gt 0 ]]; do
  case $1 in
    -rs)
      if [ -n "$2" ]; then
        REMAP_ARGS="-rs $2"
        shift 2
      else
        echo "Error: -rs requires a schema name"
        exit 1
      fi
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

# if user exists in .env file
if user_in_env_bool "$USERNAME_UPPER"; then
  # check if user is in the database
  if user_exists_in_db "$USERNAME_UPPER"; then
    echo "User $USERNAME_UPPER exists in the database"

    if [ "$SKIP_CONFIRMATION" = false ]; then
      read -p "Overwriting $USERNAME_UPPER with import. Do you want to continue? (y/n) " answer

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

./scripts/sync-backups-folder.sh

echo "Importing $USERNAME_UPPER"

# check if .dmp file exists in backups/import
if [ -f ./backups/import/"$USERNAME_LOWER".dmp ]; then
  echo "Importing datapump from ./backups/import/$USERNAME_LOWER.dmp"
  ./scripts/import-datapump.sh "$USERNAME_UPPER" "$REMAP_ARGS"
else
  echo "No .dmp file found at ./backups/import/$USERNAME_LOWER.dmp"
fi


USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

# Handle APEX workspace and apps
APEX_DIR="./backups/import/apex/$USERNAME_LOWER"
if [ -d "$APEX_DIR" ]; then
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
  
  # Import workspace file as sys user
  if [ -n "$WORKSPACE_FILE" ]; then
    echo "Importing APEX workspace from $(basename "$WORKSPACE_FILE") as SYS user"
    sql -name "$DB_CONN_NAME" <<SQL
@$WORKSPACE_FILE
exit;
SQL
    echo "APEX workspace import completed"
  fi
  
  # Import app files
  if [ -n "$APP_FILES" ]; then
    echo "Importing APEX applications"
    for APP_FILE in $APP_FILES; do
      echo "Importing $(basename "$APP_FILE") as SYS user"
      sql -name "$DB_CONN_NAME" <<SQL
@$APP_FILE
exit;
SQL
    done
    echo "APEX applications import completed"
  fi
else
  echo "No APEX directory found at $APEX_DIR"
fi

# Handle ORDS REST schema
ORDS_DIR="./backups/import/ords/$USERNAME_LOWER"
REST_SCHEMA_FILE="$ORDS_DIR/rest_schema.sql"
if [ -f "$REST_SCHEMA_FILE" ]; then
  echo "Importing ORDS REST schema from $REST_SCHEMA_FILE as $USERNAME_UPPER user"
  sql -name "$USER_DB_CONN_NAME" <<SQL
@$REST_SCHEMA_FILE
exit;
SQL
  echo "ORDS REST schema import completed"
else
  echo "No ORDS REST schema file found at $REST_SCHEMA_FILE"
fi
