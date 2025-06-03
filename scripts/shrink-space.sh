#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

sql -name "$DB_CONN_NAME" <<SQL

prompt Space usage before shrinking:
SELECT 
    ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS current_gb
FROM dba_data_files
;

prompt Shrinking tablespaces:

begin
  for rec in (
    select tablespace_name
      from user_tablespaces
     where tablespace_name like 'TBS_%'
        or tablespace_name like 'UNDOTBS%'
  )
  loop
    dbms_space.shrink_tablespace(rec.tablespace_name);
  end loop;
end;
/

prompt Space usage after shrinking:
SELECT 
    ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS current_gb
FROM dba_data_files
;
SQL

echo "Resource to further optimize space usage: https://connor-mcdonald.com/2023/12/18/the-ultimate-database-free-edition/"
