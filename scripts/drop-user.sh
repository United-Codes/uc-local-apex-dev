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

  sql -name $DB_CONN_NAME <<SQL
    select user from dual;

    begin
      APEX_INSTANCE_ADMIN.REMOVE_WORKSPACE('${USERNAME_UPPER}');
    end;
    /

    commit;

    -- kill active sessions
    BEGIN
      FOR s IN (SELECT sid, serial# FROM v\$session WHERE username = '$USERNAME_UPPER')
      LOOP
        EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
      END LOOP;
    END;
    /

    DROP USER $USERNAME_UPPER CASCADE;

    exit;
SQL

  echo "dropped schema $USERNAME_UPPER."

  echo "You have to manually remove the connection from connmgr :/. I hope SQLcl implements this soon."
  # USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"
  #   sql -nolog <<SQL
  #     connmgr ...
  # SQL

  # remove user from .env file
  sed -i '' "/${USERNAME_UPPER}_USER_PASSWORD/d" ./.env

  echo "Removed user $USERNAME_UPPER from .env file"
else
  echo "Stopping..."
fi
