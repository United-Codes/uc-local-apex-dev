set -e

source ./scripts/util/load_env.sh

sql sys/$ORACLE_PASSWORD@localhost:1521/FREEPDB1 as SYSDBA <<SQL
  conn -save $DB_CONN_NAME -savepwd -replace
  exit;
SQL

echo "saved sqlcl connection"
echo "connect with 'sql -name $DB_CONN_NAME'"
