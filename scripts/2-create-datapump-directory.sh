set -e

source ./scripts/util/load_env.sh

docker exec -u oracle -it ${CONTAINER_NAME} bash -c 'cd /opt/oracle/oradata; mkdir -p datapump/import; mkdir -p datapump/export'

sql -name $DB_CONN_NAME <<SQL
  create or replace directory datapump_import_dir as '/opt/oracle/oradata/datapump/import';
  create or replace directory datapump_export_dir as '/opt/oracle/oradata/datapump/export';

  exit;
SQL

echo "created datapump directory"
echo "grant users:"
echo "'GRANT READ, WRITE ON DIRECTORY datapump_import_dir TO [schema];'"
echo "'GRANT READ, WRITE ON DIRECTORY datapump_export_dir TO [schema];'"
