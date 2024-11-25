set -e

source ./scripts/util/load_env.sh

chmod -R 777 ./backups/import
docker cp ./backups/import ${CONTAINER_NAME}:/opt/oracle/oradata/datapump/
#docker exec -u oracle -it ${CONTAINER_NAME} bash -c 'chown -R $(id -u):$(id -g) /opt/oracle/oradata/datapump/import'

docker cp ${CONTAINER_NAME}:/opt/oracle/oradata/datapump/export/ ./backups/

echo "synced backups folder"
