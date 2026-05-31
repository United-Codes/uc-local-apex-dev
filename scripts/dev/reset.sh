set -e

source ./scripts/util/load_env.sh

$DOCKER_COMPOSE stop || true
$CONTAINER_CLI rm $CONTAINER_NAME || true
$CONTAINER_CLI volume rm oradata || true

if [ -f .env ]; then
  rm .env
fi

./setup.sh
$DOCKER_COMPOSE up -d
./scripts/1-save-sqlcl-connection.sh
./scripts/2-create-datapump-directory.sh
./scripts/3-sync-backups-folder.sh
./scripts/create-user.sh movies
./scripts/import-datapump.sh movies
