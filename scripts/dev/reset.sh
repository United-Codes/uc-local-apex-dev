set -e

docker-compose stop || true
docker rm apex-24-1-23ai || true
docker volume rm oradata || true
rm .env || true
./setup.sh
docker-compose up -d
./scripts/1-save-sqlcl-connection.sh
./scripts/2-create-datapump-directory.sh
./scripts/3-sync-backups-folder.sh
./scripts/create-user.sh movies
./scripts/import-datapump.sh movies
