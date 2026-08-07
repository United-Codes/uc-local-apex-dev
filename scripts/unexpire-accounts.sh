#!/usr/bin/env bash
# desc: Unlock and unexpire DB and APEX/ORDS accounts (fixes "Account Is Locked")

set -e

source ./scripts/util/load_env.sh

sql -name "$DB_CONN_NAME" <<SQL
set serveroutput on

DECLARE
  l_unexpire_command VARCHAR2(4000);
BEGIN
  EXECUTE IMMEDIATE 'ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK';

  -- re-applying the stored password hash clears the expiry state without
  -- changing the password
  FOR acc IN (
    SELECT u.username, s.spare4, s.password
      FROM sys.dba_users u
      JOIN sys.user$ s ON s.name = u.username
     WHERE u.username = 'APEX_PUBLIC_USER'
        OR (u.oracle_maintained = 'N' AND u.account_status LIKE '%EXPIRED%')
  ) LOOP
    BEGIN
      l_unexpire_command := 'alter user "' || acc.username || q'<" identified by values '>'
        || acc.spare4 || ';' || acc.password || q'<'>';
      EXECUTE IMMEDIATE l_unexpire_command;
      dbms_output.put_line('Unexpired DB account ' || acc.username);
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('Error unexpiring DB account ' || acc.username || ': ' || sqlerrm);
    END;
  END LOOP;
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

echo "Unexpired DB accounts (incl. APEX_PUBLIC_USER) and APEX workspace accounts."
