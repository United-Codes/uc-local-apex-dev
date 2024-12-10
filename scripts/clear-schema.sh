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

read -p "Dropping schema $USERNAME_UPPER. Do you want to continue? (y/n) " answer

if [[ $answer == "y" ]] || [[ $answer == "Y" ]]; then
  echo "Continuing..."

  USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

  sql -name $USER_DB_CONN_NAME <<SQL
    select user from dual;

    @./scripts/sql/drop_all.sql

    exit;
SQL

  echo "Schema $USERNAME_UPPER is now empty."
else
  echo "Stopping..."
fi
