#!/usr/bin/env bash
# desc: Stop database account passwords from expiring

set -e

source ./scripts/util/load_env.sh

sql -name "$DB_CONN_NAME" <<SQL
alter profile default limit password_life_time unlimited;

begin
  -- APEX workspace account lifetime via the supported public API instead of
  -- poking wwv_flow_platform_prefs directly. 9999 is the max the API allows
  -- (validated against [1-9][0-9]{0,3}); ~27 years, i.e. effectively never for
  -- a dev environment. The old direct table update used 10000 to bypass this.
  apex_instance_admin.set_parameter('ACCOUNT_LIFETIME_DAYS', 9999);
  commit;
end;
/
SQL

echo "Disabled password expiration for DB accounts (default profile) and APEX workspace accounts."
