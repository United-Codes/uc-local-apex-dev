#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user_in_env.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name>"
  exit 1
fi
USERNAME=$1

USERNAME_UPPER=$(echo "$USERNAME" | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

if [[ $USERNAME_LOWER == "sys" ]]; then
  echo "Cannot drop SYS schema"
  exit 1
fi

user_in_env "$USERNAME"

read -r -p "Dropping all objects in schema $USERNAME_UPPER. Do you want to continue? (y/n) " answer

if [[ $answer == "y" ]] || [[ $answer == "Y" ]]; then
  echo "Continuing..."

  USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

  sql -name "$USER_DB_CONN_NAME" <<SQL
    select user from dual;

    @./scripts/sql/drop_all.sql

    exit;
SQL

  echo "Schema $USERNAME_UPPER is now empty."
else
  echo "Stopping..."
fi

read -r -p "Drop APEX applications? (y/n) " answer2

if [[ $answer2 == "y" ]] || [[ $answer2 == "Y" ]]; then
  sql -name "$USER_DB_CONN_NAME" <<SQL
    select user from dual;

    set serveroutput on size unlimited

    @./scripts/sql/drop_apex_apps.sql

    exit;
SQL
fi
