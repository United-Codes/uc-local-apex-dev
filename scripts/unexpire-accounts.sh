#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

sql -name "$DB_CONN_NAME" <<SQL
DECLARE
  c_username CONSTANT VARCHAR2(128) := 'APEX_PUBLIC_USER';
  l_unexpire_command VARCHAR2(4000);
BEGIN
  EXECUTE IMMEDIATE 'ALTER USER ' || c_username || ' ACCOUNT UNLOCK';

  SELECT 'alter user ' || name || q'< identified by values '>' || spare4 || ';' || password || q'<'>'
    INTO l_unexpire_command
    FROM sys.user$
   WHERE name = c_username;

  EXECUTE IMMEDIATE l_unexpire_command;
END;
/


begin
      for c1 in (select user_name from apex_workspace_apex_users) loop
        begin
          apex_util.unexpire_workspace_account(p_user_name => c1.user_name);
        exception
          when others then
            null;
        end;
      end loop;

      commit;
end;
/
SQL

echo "Unexpired APEX_PUBLIC_USER and APEX workspace accounts."
