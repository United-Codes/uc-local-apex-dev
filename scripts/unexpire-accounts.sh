#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on

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


declare
  l_workspace_id number;
begin
  for ws in (select workspace from apex_workspaces) 
  loop
    begin
      l_workspace_id := apex_util.find_security_group_id (p_workspace => ws.workspace);
      apex_util.set_security_group_id (p_security_group_id => l_workspace_id);
      
      for c1 in (select user_name from apex_workspace_apex_users where workspace_id = l_workspace_id) loop
        begin
          apex_util.unexpire_workspace_account(p_user_name => c1.user_name);
        exception
          when others then
            dbms_output.put_line('Error unexpiring account ' || c1.user_name || ' in workspace ' || ws.workspace || ': ' || sqlerrm);
        end;
      end loop;

    exception
      when others then
        dbms_output.put_line('Error setting workspace ' || ws.workspace || ': ' || sqlerrm);
    end;
  end loop;
end;
/

SQL

echo "Unexpired APEX_PUBLIC_USER and APEX workspace accounts."
