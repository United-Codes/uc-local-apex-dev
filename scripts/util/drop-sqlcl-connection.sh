#!/usr/bin/env bash

sql /nolog <<SQL
  connmgr delete -conn "${DB_CONN_BASE}-${USERNAME_LOWER}"
  exit;
SQL

echo "dropped sqlcl connection: "${DB_CONN_BASE}-${USERNAME_LOWER}""
echo ""
