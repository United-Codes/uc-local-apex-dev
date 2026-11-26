#!/usr/bin/env bash
# desc: Copy ./backups/import into the container and pull exports back out

set -e

source ./scripts/util/load_env.sh

# Usage: sync-backups-folder.sh [push|pull|both] [schema]
#
# Without a schema, both directions copy the WHOLE tree. That is what the
# `sync-backups-folder` command does.
#
# With a schema, only the DataPump files of that schema move: <schema>.dmp on
# push, <schema>.dmp and <schema>.log on pull. backup-user.sh and
# import-backup.sh use this. A whole-tree copy per schema is slow, and it is
# unsafe while two jobs run: one job can rewrite or read a dump that another job
# still uses. The APEX and ORDS files never enter the container, because the
# scripts read them from the host.
DIRECTION="${1:-both}"
SCHEMA_LOWER=$(echo "${2:-}" | tr '[:upper:]' '[:lower:]')
DP_DIR="/opt/oracle/oradata/datapump"

case "$DIRECTION" in
push | pull | both) ;;
*)
  echo "Usage: $0 [push|pull|both] [schema]"
  exit 1
  ;;
esac

if [ -n "$SCHEMA_LOWER" ] && [ "$DIRECTION" = "both" ]; then
  echo "Error: a schema needs the direction push or pull"
  exit 1
fi

if [ "$DIRECTION" = "push" ] || [ "$DIRECTION" = "both" ]; then
  mkdir -p ./backups/import
  if [ -n "$SCHEMA_LOWER" ]; then
    if [ ! -f "./backups/import/${SCHEMA_LOWER}.dmp" ]; then
      echo "Error: ./backups/import/${SCHEMA_LOWER}.dmp not found" >&2
      exit 1
    fi
    chmod 666 "./backups/import/${SCHEMA_LOWER}.dmp"
    $CONTAINER_CLI exec "${CONTAINER_NAME}" mkdir -p "${DP_DIR}/import"
    $CONTAINER_CLI cp "./backups/import/${SCHEMA_LOWER}.dmp" \
      "${CONTAINER_NAME}:${DP_DIR}/import/${SCHEMA_LOWER}.dmp"
    echo "pushed ${SCHEMA_LOWER}.dmp into ${CONTAINER_NAME}"
  else
    chmod -R 777 ./backups/import
    $CONTAINER_CLI cp ./backups/import "${CONTAINER_NAME}":${DP_DIR}/
    echo "pushed ./backups/import into ${CONTAINER_NAME}"
  fi
fi

if [ "$DIRECTION" = "pull" ] || [ "$DIRECTION" = "both" ]; then
  mkdir -p ./backups/export
  if [ -n "$SCHEMA_LOWER" ]; then
    $CONTAINER_CLI cp "${CONTAINER_NAME}:${DP_DIR}/export/${SCHEMA_LOWER}.dmp" \
      "./backups/export/${SCHEMA_LOWER}.dmp"
    $CONTAINER_CLI cp "${CONTAINER_NAME}:${DP_DIR}/export/${SCHEMA_LOWER}.log" \
      "./backups/export/${SCHEMA_LOWER}.log" 2>/dev/null || true
    echo "pulled ${SCHEMA_LOWER}.dmp from ${CONTAINER_NAME} into ./backups/export"
  else
    $CONTAINER_CLI cp "${CONTAINER_NAME}:${DP_DIR}/export/" ./backups/
    echo "pulled exports from ${CONTAINER_NAME} into ./backups/export"
  fi
fi
