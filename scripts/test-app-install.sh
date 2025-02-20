#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <path to application file>"
  exit 1
fi

# If the input path is relative (doesn't start with /)
if [[ "${1}" != /* ]]; then
  # Make it absolute using the original working directory
  echo "path: ${ORIGINAL_PWD}/${1}"
  FILE_NAME=$(realpath "${ORIGINAL_PWD}/${1}")
else
  FILE_NAME="${1}"
fi

# check if file exists
if [ ! -f "$FILE_NAME" ]; then
  echo "File $FILE_NAME not found"
  exit 1
fi

# if file extension is .pkb
if [[ $FILE_NAME != *.sql ]]; then
  echo "File $FILE_NAME is not a SQL file"
  exit 1
fi

RANDOM_NUMBER=$(shuf -i 0-9 -n 6 | tr -d '\n')
USER_NAME="TESTINSTALL_$RANDOM_NUMBER"

./scripts/create-user.sh $USER_NAME

echo "user created"

USERNAME_LOWER=$(echo $USER_NAME | tr '[:upper:]' '[:lower:]')
USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"
echo "user db conn name: $USER_DB_CONN_NAME"

echo "installing application"

sql -name $USER_DB_CONN_NAME <<SQL
set serveroutput on size unlimited

begin
  apex_application_install.set_workspace( p_workspace => '$USER_NAME' );
  apex_application_install.set_schema( p_schema => '$USER_NAME' );
  apex_application_install.set_application_name( p_application_name => '$USER_NAME' );
  apex_application_install.set_application_alias( p_application_alias => '$RANDOM_NUMBER' );
  apex_application_install.set_application_id( p_application_id => $RANDOM_NUMBER );
end;
/

@${FILE_NAME}
SQL

echo "application installed"

./scripts/drop-user.sh $USER_NAME

echo "user $USER_NAME dropped"
