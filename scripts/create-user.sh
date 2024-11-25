set -e

source ./scripts/util/load_env.sh
source ./scripts/util/generate_password.sh

skip_workspace=false

usage() {
  echo "Usage: $0  <schema_name> < --skip_workspace>"
  exit 1
}

# check parameter is passed
if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name> < --skip_workspace>"
  exit 1
fi
USERNAME=$1
shift # Remove schema_name from argument list

# Process remaining arguments for --skip-workspace
while [[ $# -gt 0 ]]; do
  case $1 in
  --skip-workspace)
    skip_workspace=true
    shift
    ;;
  *)
    echo "Error: Unknown parameter '$1'"
    echo "Usage: $0 <schema_name> [--skip-workspace]"
    exit 1
    ;;
  esac
done

USERNAME_UPPER=$(echo $USERNAME | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo $USERNAME | tr '[:upper:]' '[:lower:]')
USER_PASSWORD=$(generate_password)

echo "${USERNAME_UPPER}_USER_PASSWORD=\"$USER_PASSWORD\"" >>.env

sql -name $DB_CONN_NAME <<SQL
  create tablespace tbs_${USERNAME_LOWER}
    datafile 'tbs_${USERNAME_LOWER}.dat'
      size 10M
      reuse
      autoextend on next 2M;

  create user ${USERNAME}
    identified by "${USER_PASSWORD}"
    default tablespace tbs_${USERNAME_LOWER}
  ;

  grant create session to ${USERNAME};
  grant create table to ${USERNAME};
  grant create view to ${USERNAME};
  grant create any trigger to ${USERNAME};
  grant create any procedure to ${USERNAME};
  grant create sequence to ${USERNAME};
  grant create synonym to ${USERNAME};
  grant unlimited tablespace to ${USERNAME};

  -- also recommended when with apex workspace
  grant create cluster to ${USERNAME};
  grant create dimension to ${USERNAME};
  grant create indextype to ${USERNAME};
  grant create job to ${USERNAME};
  grant create materialized view to ${USERNAME};
  grant create operator to ${USERNAME};
  grant create procedure to ${USERNAME};
  grant create trigger to ${USERNAME};
  grant create type to ${USERNAME};
  grant create any context to ${USERNAME};
  grant create mle to ${USERNAME};
  grant create property graph to ${USERNAME};
  grant execute dynamic mle to ${USERNAME};

  grant read, write on directory datapump_import_dir to ${USERNAME};
  grant read, write on directory datapump_export_dir to ${USERNAME};
  exit;
SQL

echo ">>>>"
echo "created user"

if [ "$skip_workspace" = true ]; then
  sql -name $DB_CONN_NAME <<SQL
    BEGIN
      APEX_INSTANCE_ADMIN.ADD_WORKSPACE (
        p_workspace          => '${USERNAME}',
        p_primary_schema     => '${USERNAME}' 
      );

      commit;

      APEX_UTIL.SET_SECURITY_GROUP_ID(
        APEX_UTIL.FIND_SECURITY_GROUP_ID(p_workspace => '${USERNAME}')
      );

      commit;

      APEX_UTIL.CREATE_USER(
        p_user_name                    => '${USERNAME}',
        p_web_password                 => 'Welcome_1',
        p_email_address                => '${USERNAME}@localhost.com',
        p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
        p_default_schema               => '${USERNAME}',
        p_allow_access_to_schemas      => '${USERNAME}',
        p_change_password_on_first_use => 'N'
      );

      commit;

      APEX_UTIL.CREATE_USER(
        p_user_name                    => 'ADMIN',
        p_web_password                 => 'Welcome_1',
        p_email_address                => 'admin@localhost.com',
        p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
        p_default_schema               => '${USERNAME}',
        p_allow_access_to_schemas      => '${USERNAME}',
        p_change_password_on_first_use => 'N'
      );

      commit;
    END;
    /
    exit;
SQL

  echo ">>>>"
  echo "created workspace. Access with username 'ADMIN' or ${USERNAME} and password 'Welcome_1'"
  echo "http://localhost:8181/ords/r/apex/workspace-sign-in/oracle-apex-sign-in"

fi

USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

sql ${USERNAME_LOWER}/${USER_PASSWORD}@localhost:1521/FREEPDB1 <<SQL
  conn -save ${USER_DB_CONN_NAME} -savepwd -replace
  exit;
SQL

echo ">>>>"
echo "saved sqlcl connection"
echo "connect with 'sql -name $USER_DB_CONN_NAME'"
