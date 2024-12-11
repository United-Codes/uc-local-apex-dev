#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user_in_env.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name>"
  exit 1
fi
USERNAME=$1

user_in_env $USERNAME

USERNAME_UPPER=$(echo $USERNAME | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo $USERNAME | tr '[:upper:]' '[:lower:]')

USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

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

sql -name $USER_DB_CONN_NAME <<SQL
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
if [ ! -d ./backups/export/apex/$USERNAME_LOWER ]; then
  mkdir -p ./backups/export/apex/$USERNAME_LOWER
fi

cd ./backups/export/apex/$USERNAME_LOWER

sql -name $USER_DB_CONN_NAME <<SQL
    select user from dual;

    column workspace_id new_value workspace_id
    select workspace_id from apex_workspaces fetch first row only;

    apex export-workspace -woi &workspace_id
    apex export-all-applications -woi &workspace_id

    exit;
SQL
