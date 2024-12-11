#!/usr/bin/env bash

sql sys/$ORACLE_PASSWORD@localhost:1521/FREEPDB1 as SYSDBA <<SQL
  select user from dual;

  conn -save $DB_CONN_NAME -savepwd -replace
  exit;
SQL

echo "saved sqlcl connection"
echo "connect with 'sql -name $DB_CONN_NAME'"
echo ""
