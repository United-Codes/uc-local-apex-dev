#!/usr/bin/env bash
# desc: Back up everything, wipe the database, install a new one, and import everything again

set -e

# One command for the "start with a clean database" workflow:
#
#   1. backup-all           export every schema, APEX workspace and ORDS module
#   2. stage                copy ./backups/export to ./backups/import
#   3. wipe                 stop the stack, delete the database volume and ./ords-config
#   4. install.sh           install a new database with the image in docker-compose.yml
#   5. import-all           restore every schema, then the roles and grants
#
# Change the image tag in docker-compose.yml BEFORE you run this command. .env
# stays, so the passwords stay the same.
#
# Usage: rebuild.sh [-y] [-j <jobs>] [--accept-losses]
#   -y                do not ask for confirmation
#   -j <n>            run n DataPump imports at once (see import-all)
#   --accept-losses   with -y, delete the database although the backup cannot hold
#                     everything (secrets such as credentials). Without it, -y stops.
#
# Exit status: 0 everything came back. 1 a step failed. 2 everything that a backup
# can hold came back, but secrets must be entered again (the list is printed).

source ./scripts/util/load_env.sh

ASSUME_YES=false
ACCEPT_LOSSES=false
JOBS=1
while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes)
      ASSUME_YES=true
      shift
      ;;
    --accept-losses)
      ACCEPT_LOSSES=true
      shift
      ;;
    -j | --jobs)
      [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || {
        echo "Error: -j needs a positive number"
        exit 1
      }
      JOBS="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [-y] [-j <jobs>] [--accept-losses]"
      exit 1
      ;;
  esac
done

VOLUME="${DB_VOLUME_NAME:-oradata-26ai}"

echo ""
echo "== Step 1/5: backup-all"
./scripts/backup-all.sh

# Do not delete anything that cannot be restored. backup-all exits with an error
# if a schema fails, and set -e has stopped us then. Check the files as well.
shopt -s nullglob
dumps=(./backups/export/*.dmp)
shopt -u nullglob
good_dumps=()
for f in "${dumps[@]}"; do
  case "$f" in *_bkp.dmp) continue ;; esac
  [ -s "$f" ] && good_dumps+=("$f")
done
if [ ${#good_dumps[@]} -eq 0 ]; then
  echo "Error: the backup produced no dump file. Nothing was deleted." >&2
  exit 1
fi
for f in schemas.tsv 00_pre.sql 10_post.sql; do
  if [ ! -s "./backups/export/recovery/$f" ]; then
    echo "Error: ./backups/export/recovery/$f is missing. Nothing was deleted." >&2
    exit 1
  fi
done

# Ask only now: the backup is done, and the list of what it cannot hold is known.
UNRECOVERABLE=./backups/export/recovery/unrecoverable.txt
HAS_LOSSES=false
if [ -f "$UNRECOVERABLE" ] && grep -q '[^[:space:]]' "$UNRECOVERABLE"; then
  HAS_LOSSES=true
fi
echo ""
if [ "$HAS_LOSSES" = true ]; then
  echo "The backup cannot hold these. You must enter or create them again after the rebuild:"
  grep -v '^[[:space:]]*$' "$UNRECOVERABLE" | sed 's/^/  - /'
  echo ""
fi
if [ "$ASSUME_YES" = true ]; then
  if [ "$HAS_LOSSES" = true ] && [ "$ACCEPT_LOSSES" = false ]; then
    echo "Error: stopping before the delete, because of the list above." >&2
    echo "       Run again with --accept-losses to delete the database anyway." >&2
    exit 1
  fi
else
  echo "This command DELETES the database volume '$VOLUME' and the contents of"
  echo "./ords-config. It installs a new database and imports the backup."
  read -r -p "Type the volume name to continue: " answer
  if [ "$answer" != "$VOLUME" ]; then
    echo "Stopping. Nothing was deleted. The backup is in ./backups/export."
    exit 1
  fi
fi

echo ""
echo "== Step 2/5: copy ./backups/export to ./backups/import"
mkdir -p ./backups/import
rm -rf ./backups/import/apex ./backups/import/ords ./backups/import/recovery ./backups/import/logs
rm -f ./backups/import/*.dmp ./backups/import/*.log
for f in "${good_dumps[@]}"; do
  cp "$f" ./backups/import/
done
for d in ords recovery; do
  [ -d "./backups/export/$d" ] && cp -R "./backups/export/$d" "./backups/import/$d"
done
if [ -d ./backups/export/apex ]; then
  mkdir -p ./backups/import/apex
  for d in ./backups/export/apex/*/; do
    [ "$(basename "$d")" = "bkp" ] && continue
    cp -R "$d" ./backups/import/apex/
  done
fi

echo ""
echo "== Step 3/5: wipe the database"
# compose down, not stop.sh: the database is about to be deleted, so a clean
# shutdown and the space check have no value.
$DOCKER_COMPOSE -f docker-compose.yml down
$CONTAINER_CLI volume rm "$VOLUME"
if ! rm -rf ./ords-config/* ./ords-config/.[!.]* 2>/dev/null; then
  echo "Error: cannot delete the contents of ./ords-config (files of another owner)." >&2
  echo "       Delete them with sudo, then run ./install.sh and ./local-26ai.sh import-all -y." >&2
  exit 1
fi

echo ""
echo "== Step 4/5: install a new database"
./install.sh

# Components that the old database had. Grants on them come with the import.
PARAMS=./backups/import/recovery/params.tsv
if grep -qx 'dbms_cloud|installed' "$PARAMS" 2>/dev/null; then
  echo ""
  echo "== Step 4/5: install DBMS_CLOUD (the old database had it)"
  ./scripts/install-dbms-cloud.sh
fi
if grep -qx 'utplsql|installed' "$PARAMS" 2>/dev/null; then
  echo ""
  echo "== Step 4/5: install utPLSQL (the old database had it)"
  ./scripts/install-utplsql.sh
fi

echo ""
echo "== Step 5/5: import-all"
./scripts/import-all.sh -y -j "$JOBS"

echo ""
echo "Rebuild finished."
if [ "$HAS_LOSSES" = true ]; then
  echo ""
  echo "Do these steps by hand. No backup holds them:"
  grep -v '^[[:space:]]*$' "$UNRECOVERABLE" | sed 's/^/  - /'
  exit 2
fi
