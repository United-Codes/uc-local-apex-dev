#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

# check parameter is passed
if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name> [-rs <remap_schema_name>]"
  exit 1
fi

USERNAME=$1
USERNAME_UPPER=$(echo $USERNAME | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo $USERNAME | tr '[:upper:]' '[:lower:]')
SQLCRED_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

# Parse optional -rs parameter
REMAP_SCHEMA=""
SCHEMA_NAME="${USERNAME_LOWER}"
if [ "$2" = "-rs" ] && [ -n "$3" ]; then
  REMAP_SCHEMA_NAME=$(echo $3 | tr '[:upper:]' '[:lower:]')
  REMAP_SCHEMA="-remapschemas ${REMAP_SCHEMA_NAME}=${USERNAME_LOWER}"
  SCHEMA_NAME="${REMAP_SCHEMA_NAME}"
fi

sql -name $SQLCRED_NAME <<SQL
  select user from dual;

  datapump import -
  -schemas ${SCHEMA_NAME} -
  -directory datapump_import_dir -
  -dumpfile ${USERNAME_LOWER}.dmp -
  -logfile ${USERNAME_LOWER}.log -
  -version latest ${REMAP_SCHEMA}

  datapump import -
  -schemas ${SCHEMA_NAME} -
  -directory datapump_import_dir -
  -dumpfile ${USERNAME_LOWER}.dmp -
  -logfile ${USERNAME_LOWER}.log -
  -version latest ${REMAP_SCHEMA}

  commit;

  exit;
SQL
