#!/usr/bin/env bash
# desc: Copy ./backups/import into the container and pull exports back out

set -e

source ./scripts/util/load_env.sh

# Both directions copy the WHOLE tree, so a caller that only produced one new
# dump file must not pay for the other direction. backup-user.sh pulls, and
# import-backup.sh pushes. With no argument both directions run, which is what
# the `sync-backups-folder` command does.
DIRECTION="${1:-both}"

case "$DIRECTION" in
push | pull | both) ;;
*)
  echo "Usage: $0 [push|pull|both]"
  exit 1
  ;;
esac

if [ "$DIRECTION" = "push" ] || [ "$DIRECTION" = "both" ]; then
  mkdir -p ./backups/import
  chmod -R 777 ./backups/import
  $CONTAINER_CLI cp ./backups/import "${CONTAINER_NAME}":/opt/oracle/oradata/datapump/
  echo "pushed ./backups/import into ${CONTAINER_NAME}"
fi

if [ "$DIRECTION" = "pull" ] || [ "$DIRECTION" = "both" ]; then
  mkdir -p ./backups
  $CONTAINER_CLI cp "${CONTAINER_NAME}":/opt/oracle/oradata/datapump/export/ ./backups/
  echo "pulled exports from ${CONTAINER_NAME} into ./backups/export"
fi
