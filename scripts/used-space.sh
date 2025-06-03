#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

sql -name "$DB_CONN_NAME" <<SQL
SELECT 
    ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS current_gb,
    12 AS limit_gb,
    ROUND((SUM(bytes) / 1024 / 1024 / 1024 / 12) * 100, 2) AS percent_of_limit,
    CASE 
        WHEN SUM(bytes) / 1024 / 1024 / 1024 > 11 THEN 'CRITICAL'
        WHEN SUM(bytes) / 1024 / 1024 / 1024 > 10 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM dba_data_files
;

  select df.tablespace_name "Tablespace",
       df.totalspace "Total MB",
       totalusedspace "Used MB",
       (df.totalspace - tu.totalusedspace) "Free MB",
       round(100 * ( (df.totalspace - tu.totalusedspace)/ df.totalspace)) "Pct. Free"
  from (select tablespace_name,
               round(sum(bytes) / 1048576) TotalSpace
          from dba_data_files 
         group by tablespace_name) df,
       (select round(sum(bytes)/(1024*1024)) totalusedspace,
               tablespace_name
          from dba_segments 
         group by tablespace_name) tu
 where df.tablespace_name = tu.tablespace_name 
 order by totalspace desc;
SQL

echo "Run the shrink-space script to reduce space usage"
