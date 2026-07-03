#!/usr/bin/env bash
# desc: Drop a schema including its tablespace and datafile (-y skips confirmation)

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user_in_env.sh
source ./scripts/util/user-exists-in-db.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name> [-y]"
  exit 1
fi
USERNAME="$1"
user_in_env "$USERNAME"

# Check for -y flag (skip the confirmation prompt), matching clear-schema.sh
AUTO_YES=false
if [[ "$2" == "-y" ]]; then
  AUTO_YES=true
fi

USERNAME_UPPER=$(echo "$USERNAME" | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

# create-user.sh gives every schema its own tablespace (tbs_<user>); drop it too
# so the datafile is reclaimed from disk instead of lingering as an orphan.
TBS="tbs_${USERNAME_LOWER}"

if ! user_exists_in_db "$USERNAME"; then
  echo "Note: user $USERNAME_UPPER does not exist in the database; will still drop"
  echo "a leftover tablespace ($TBS) and clean up .env / the stored connection."
fi

if [[ "$AUTO_YES" == "true" ]]; then
  echo "Dropping schema $USERNAME_UPPER and its tablespace $TBS (auto-confirmed with -y)..."
  answer="y"
else
  read -r -p "Dropping schema $USERNAME_UPPER and its tablespace $TBS. Do you want to continue? (y/n) " answer
fi

if [[ $answer == "y" ]] || [[ $answer == "Y" ]]; then
  echo "Continuing..."

  # Each statement is guarded so the script works whether or not the user /
  # tablespace still exist (e.g. a half-created schema, or a re-run).
  sql -name "$DB_CONN_NAME" <<SQL
    select user from dual;
    set serveroutput on size 1000000 format wrapped
    declare
       e_no_workspace exception;
       pragma exception_init (e_no_workspace, -20987);
    begin
      APEX_INSTANCE_ADMIN.REMOVE_WORKSPACE('${USERNAME_UPPER}');
    exception
      when e_no_workspace
      then
        sys.dbms_output.put_line ('No Workspace to be removed');
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

    begin
      execute immediate 'DROP USER $USERNAME_UPPER CASCADE';
      dbms_output.put_line('dropped user $USERNAME_UPPER');
    exception when others then
      dbms_output.put_line('skip drop user: '||sqlerrm);
    end;
    /

    -- Reclaim the per-user tablespace + datafile. Restricted to the tbs_<user>
    -- name create-user.sh assigns, so a shared tablespace can never be hit here.
    begin
      execute immediate 'DROP TABLESPACE $TBS INCLUDING CONTENTS AND DATAFILES';
      dbms_output.put_line('dropped tablespace $TBS');
    exception when others then
      dbms_output.put_line('skip drop tablespace $TBS: '||sqlerrm);
    end;
    /

    exit;
SQL

  echo "dropped schema $USERNAME_UPPER."

  # echo "You have to manually remove the connection from connmgr :/. I hope SQLcl implements this soon."
  source ./scripts/util/drop-sqlcl-connection.sh

  # remove user from .env file
  sed -e "/${USERNAME_UPPER}_USER_PASSWORD/ s/^/# /" -e "/${USERNAME_UPPER}_USER_PASSWORD/ s/$/ # deleted/" ./.env > ./.env.tmp && mv ./.env.tmp ./.env

  echo "Commented out user $USERNAME_UPPER in .env file"
else
  echo "Stopping..."
fi
