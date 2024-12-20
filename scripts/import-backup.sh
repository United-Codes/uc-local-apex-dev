#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user_in_env.sh
source ./scripts/util/user-exists-in-db.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name>"
  exit 1
fi
USERNAME=$1
USERNAME_UPPER=$(echo $USERNAME | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo $USERNAME | tr '[:upper:]' '[:lower:]')

# if user exists in .env file
if user_in_env_bool $USERNAME_UPPER; then
  # check if user is in the database
  if user_exists_in_db $USERNAME_UPPER; then
    echo "User $USERNAME_UPPER exists in the database"

    read -p "Overwriting $USERNAME_UPPER with import. Do you want to continue? (y/n) " answer

    if [[ $answer == "y" ]] || [[ $answer == "Y" ]]; then
      echo "Continuing..."
    else
      echo "Stopping..."
      exit 0
    fi
  else
    echo "User $USERNAME_UPPER does not exist in the database"
    echo "Creating new user $USERNAME_UPPER"

    # scripts checks if user exists in the .env file
    ./scripts/create-user.sh $USERNAME_UPPER
  fi
else
  echo "User $USERNAME_UPPER does not exist in the .env file"
  echo "Creating new user $USERNAME_UPPER"

  ./scripts/create-user.sh $USERNAME_UPPER
fi

./scripts/sync-backups-folder.sh

echo "Importing $USERNAME_UPPER"

# check if .dmp file exists in backups/import
if [ -f ./backups/import/$USERNAME_LOWER.dmp ]; then
  echo "Importing datapump from ./backups/import/$USERNAME_LOWER.dmp"
  ./scripts/import-datapump.sh $USERNAME_UPPER
else
  echo "No .dmp file found at ./backups/import/$USERNAME_LOWER.dmp"
fi
