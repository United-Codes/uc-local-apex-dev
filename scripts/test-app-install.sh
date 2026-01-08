#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user-exists-in-db.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <path to application file> [-y]"
  exit 1
fi


# Check for -y flag
AUTO_YES=false
if [[ "$2" == "-y" ]]; then
  AUTO_YES=true
fi


# If the input path is relative (doesn't start with /)
if [[ "${1}" != /* ]]; then
  # Make it absolute using the original working directory
  FILE_NAME=$(realpath "${ORIGINAL_PWD}/${1}")
else
  FILE_NAME="${1}"
fi

echo "path: ${FILE_NAME}"

# Create a temporary symbolic link with no spaces
TEMP_FILE="/tmp/temp_sql_file_$(date +%s).sql"
ln -sf "${FILE_NAME}" "${TEMP_FILE}"
echo "Created temporary link: ${TEMP_FILE}"

FILE_NAME="${TEMP_FILE}"
echo "symbolic link: ${FILE_NAME}"

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
USER_NAME="UC_TESTINSTALL_1"

if user_exists_in_db $USER_NAME; then
  if [[ "$AUTO_YES" == "true" ]]; then
    ./scripts/clear-schema.sh $USER_NAME -y
  else
    ./scripts/clear-schema.sh $USER_NAME
  fi
else
  echo "user $USER_NAME does not exist"
  ./scripts/create-user.sh $USER_NAME
  echo "user $USER_NAME created"
fi

USERNAME_LOWER=$(echo $USER_NAME | tr '[:upper:]' '[:lower:]')
USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"
echo "user db conn name: $USER_DB_CONN_NAME"

echo "installing application with ID: $RANDOM_NUMBER"
echo "..."

sql -name "$USER_DB_CONN_NAME" <<SQL
set serveroutput on size unlimited

begin
  apex_application_install.set_workspace( p_workspace => '$USER_NAME' );
  apex_application_install.set_schema( p_schema => '$USER_NAME' );
  apex_application_install.set_application_name( p_application_name => '$USER_NAME' );
  apex_application_install.set_application_alias( p_application_alias => '$RANDOM_NUMBER' );
  apex_application_install.set_application_id( p_application_id => $RANDOM_NUMBER );

  apex_application_install.set_auto_install_sup_obj( p_auto_install_sup_obj => true );
end;
/

@"${FILE_NAME}"

begin 
  apex_util.set_security_group_id
    (p_security_group_id => apex_application_install.get_workspace_id);
  apex_app_object_dependency.scan( p_application_id => $RANDOM_NUMBER );
end;
/

prompt Application installed

prompt user objects:
SELECT object_type, count(object_name)
from user_objects
group by object_type;

prompt Invalid objects:
SELECT object_type, object_name
FROM user_objects
WHERE status = 'INVALID';

prompt APEX object dependency scan errors:
select application_id
     , page_id
     , component_display_name
     , property_name
     , code_fragment
     , error_message 
  from apex_used_db_object_comp_props where error_message is not null;

SQL

# Remove the temporary symbolic link
if [[ -L "${TEMP_FILE}" ]]; then
  rm "${TEMP_FILE}"
  echo "Removed temporary symbolic link: ${TEMP_FILE}"
fi

echo "Done. You can connect to $USER_NAME to inspect the schema"
