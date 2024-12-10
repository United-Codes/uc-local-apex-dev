#!/usr/bin/env bash

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

  grant db_developer_role to ${USERNAME};
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

  grant debug connect session to ${USERNAME};
  grant debug connect any to ${USERNAME};
  grant debug any procedure to ${USERNAME};

  grant read, write on directory datapump_import_dir to ${USERNAME};
  grant read, write on directory datapump_export_dir to ${USERNAME};


  -- allow debug
  begin
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => '*',
    ace  =>  xs\$ace_type(privilege_list => xs\$name_list('jdwp'),
                         principal_name => '${USERNAME}',
                         principal_type => xs_acl.ptype_db));
  end;
  /

  exit;
SQL

echo ">>>>"
echo "created user"

if [ "$skip_workspace" = true ]; then
  echo ">>>>"
  echo "skipped workspace creation"
else
  sql -name $DB_CONN_NAME <<SQL
    BEGIN
      apex_instance_admin.add_workspace (
        p_workspace      => '${USERNAME}',
        p_primary_schema => '${USERNAME}' 
      );

      commit;

      apex_util.set_workspace( p_workspace => '${USERNAME}');

      commit;

      APEX_UTIL.CREATE_USER(
        p_user_name                    => '${USERNAME}',
        p_web_password                 => 'Welcome_1',
        p_email_address                => '${USERNAME}@localhost.com',
        p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
        p_change_password_on_first_use => 'N',
        p_default_schema               => '${USERNAME}'
      );

      commit;

      APEX_UTIL.CREATE_USER(
        p_user_name                    => 'ADMIN',
        p_web_password                 => 'Welcome_1',
        p_email_address                => 'admin@localhost.com',
        p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
        p_change_password_on_first_use => 'N',
        p_default_schema               => '${USERNAME}'
      );

      commit;

      for c1 in (select user_name from apex_workspace_apex_users) loop
        begin
          apex_util.unexpire_workspace_account(p_user_name => c1.user_name);
        exception
          when others then
            null;
        end;
      end loop;

      commit;
    END;
    /

    -- increase session timeout
    declare
      l_username varchar2(100);
    begin
      select creator 
      into l_username
      from PUBLICSYN where SNAME = 'APEX_UTIL'
      fetch first 1 row only;

      dbms_output.put_line('The creator of APEX_UTIL is ' || l_username);

      execute IMMEDIATE ' update ' || l_username || q'!.wwv_flow_companies
          set MAX_SESSION_IDLE_SEC = 604800
            , MAX_SESSION_LENGTH_SEC = 604800
        where short_name = '${USERNAME}'
        !';

      commit;

    end;
    /


    exit;
SQL

  echo ">>>>"
  echo "created workspace. Access with username 'ADMIN' or ${USERNAME} and password ' me'"
  echo "http://localhost:8181/ords/r/apex/workspace-sign-in/oracle-apex-sign-in"
fi

USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

sql ${USERNAME_LOWER}/${USER_PASSWORD}@localhost:1521/FREEPDB1 <<SQL
  conn -save ${USER_DB_CONN_NAME} -savepwd -replace

  begin
    ords.enable_schema;
  end;
  /

  exit;
SQL

echo ">>>>"
echo "saved sqlcl connection"
echo "connect with 'sql -name $USER_DB_CONN_NAME'"
