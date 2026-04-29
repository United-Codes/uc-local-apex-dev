#!/usr/bin/env bash

sql sys/$ORACLE_PASSWORD@localhost:1521/FREEPDB1 as SYSDBA <<SQL
  select user from dual;

  connmgr delete -conn "${DB_CONN_BASE}-${USERNAME_LOWER}"
  exit;
SQL

echo "dropped sqlcl connection: "${DB_CONN_BASE}-${USERNAME_LOWER}""
echo ""
