#!/usr/bin/env bash
# desc: DataPump-export a single schema incl. its APEX workspace and apps

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user_in_env.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name>"
  exit 1
fi
USERNAME=$1

user_in_env "$USERNAME"

USERNAME_UPPER=$(echo "$USERNAME" | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

ORIGINAL_PWD="$PWD"

# remove ./backups/$USERNAME_LOWER.log if it exists
if [ -f ./backups/export/${USERNAME_LOWER}.log ]; then
  rm -f ./backups/export/${USERNAME_LOWER}.log
fi

if [ -f ./backups/export/${USERNAME_LOWER}_bkp.dmp ]; then
  rm -f ./backups/export/${USERNAME_LOWER}_bkp.dmp
fi

if [ -f ./backups/export/${USERNAME_LOWER}.dmp ]; then
  mv ./backups/export/${USERNAME_LOWER}.dmp ./backups/export/${USERNAME_LOWER}_bkp.dmp
fi

sql -name "$USER_DB_CONN_NAME" <<SQL
    select user from dual;

    datapump export -
     -schemas $USERNAME_UPPER -
     -directory DATAPUMP_EXPORT_DIR -
     -dumpdirectory DATAPUMP_EXPORT_DIR -
     -dumpfile $USERNAME_LOWER.dmp -
     -logfile $USERNAME_LOWER.log -
     -version latest

    datapump export -
     -schemas $USERNAME_UPPER -
     -directory DATAPUMP_EXPORT_DIR -
     -dumpdirectory DATAPUMP_EXPORT_DIR -
     -dumpfile $USERNAME_LOWER.dmp -
     -logfile $USERNAME_LOWER.log -
     -version latest

    exit;
SQL

# move datapump from container to backups/export
./scripts/sync-backups-folder.sh

# create directory for APEX export
if [ ! -d ./backups/export/apex/"$USERNAME_LOWER" ]; then
  mkdir -p ./backups/export/apex/"$USERNAME_LOWER"
else
  # move existing files to backup folder
  if [ ! -d ./backups/export/apex/bkp/"$USERNAME_LOWER" ]; then
    mkdir -p ./backups/export/apex/bkp/"$USERNAME_LOWER"
  else
    # remove existing files
    rm -rf ./backups/export/apex/bkp/"$USERNAME_LOWER"/* || true
fi
  mv ./backups/export/apex/"$USERNAME_LOWER"/* ./backups/export/apex/bkp/"$USERNAME_LOWER" || true
fi

cd ./backups/export/apex/"$USERNAME_LOWER"

sql -name "$USER_DB_CONN_NAME" <<SQL
    select user from dual;

    column workspace_id new_value workspace_id format 99999999999999999999
    select workspace_id from apex_workspaces fetch first row only;

    declare
      l_ws_name apex_workspaces.workspace_display_name%type;
      l_sec_id number;
    begin
      select workspace_display_name
        into l_ws_name
        from apex_workspaces
       fetch first 1 row only;

      l_sec_id := apex_util.find_security_group_id(p_workspace => l_ws_name);
      apex_util.set_security_group_id (p_security_group_id => l_sec_id);
    end;
    /

    apex export-workspace -woi &workspace_id -overwrite-files
    apex export-all-applications -woi &workspace_id -overwrite-files

    exit;
SQL

cd "$ORIGINAL_PWD"

sql -name "$USER_DB_CONN_NAME" <<SQL
    select user from dual;

    set serveroutput on size unlimited

    @./scripts/sql/drop_dp_tables.sql

    exit;
SQL

# create directory for ORDS export
if [ ! -d ./backups/export/ords/"$USERNAME_LOWER" ]; then
  mkdir -p ./backups/export/ords/"$USERNAME_LOWER"
fi

cd ./backups/export/ords/"$USERNAME_LOWER"

sql -name "$USER_DB_CONN_NAME" -silent > rest_schema.sql <<SQL
  rest export schema
  exit;
SQL

cd "$ORIGINAL_PWD"


./scripts/sync-backups-folder.sh
