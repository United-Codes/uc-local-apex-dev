#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

sql -name "$DB_CONN_NAME" <<SQL
declare
  l_username varchar2(100);
begin
  select creator
    into l_username
    from PUBLICSYN where SNAME = 'APEX_UTIL'
   fetch first 1 row only;

  execute IMMEDIATE ' update ' || l_username || q'!.wwv_flow_platform_prefs
        set VALUE = 10000
      where NAME = 'ACCOUNT_LIFETIME_DAYS'
  !';
  commit;
end;
/
SQL

echo "Disabled password expiration for APEX workspace accounts."
