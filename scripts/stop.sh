#!/usr/bin/env bash
# desc: Gracefully shut down the database, then stop the containers

set -e

FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=true ;;
    *) echo "Unknown option: $arg (use --force to stop despite a CRITICAL space level)" >&2; exit 1 ;;
  esac
done

source ./scripts/util/load_env.sh

# Warn BEFORE the shutdown, because this is the last moment at which the user can
# act. The Free edition checks the 12 GB limit before the PDB opens, so a
# database that is over the limit when it stops will refuse to open on the next
# start -- in every mode, including read only and upgrade -- and cannot be
# repaired from inside. The database is definitely open here, and the next thing
# the user does is a start, so this is where the warning belongs.
#
# stop.sh runs under set -e, so the exit code must be captured. A bare call would
# abort the script on a warning and leave the database running.
space_rc=0
./scripts/used-space.sh --quiet || space_rc=$?

if [ "$space_rc" -eq 11 ]; then
  echo ""
  echo "!! CRITICAL: the database is close to the 12GB Free-edition limit."
  echo "!! If it grows past 12GB it will NOT open again, in any mode, and it"
  echo "!! cannot be repaired from inside."
  echo ""
  if [ "$FORCE" = "true" ]; then
    echo "!! --force given: skipping the shrink and stopping anyway."
    echo ""
  else
    # The database is still open, so it can still be repaired. Shrink it now and
    # check again. Stop only if the space is no longer CRITICAL. Exit non-zero
    # otherwise, so that a chained command such as "stop && podman machine stop"
    # does not run. A failure of shrink-space itself is not fatal: the re-check
    # below decides.
    echo "Running shrink-space --auto before the shutdown (purges audit records, keeps old APEX schemas)..."
    ./scripts/shrink-space.sh --auto || echo "Note: shrink-space reported a failure. Checking the space again."
    space_rc=0
    ./scripts/used-space.sh --quiet || space_rc=$?
    if [ "$space_rc" -eq 11 ]; then
      echo "" >&2
      echo "!! The database is still CRITICAL after the shrink. It was NOT stopped." >&2
      echo "!! Run ./local-26ai.sh cap-tablespaces --apply, and free more space." >&2
      echo "!! To stop it anyway, run: ./local-26ai.sh stop --force" >&2
      exit 11
    fi
    echo "The space is no longer CRITICAL. Continuing to shut down."
    echo ""
  fi
fi

case "$space_rc" in
  11) ;;   # CRITICAL with --force: already reported above
  10)
    echo ""
    echo "Warning: the database uses more than ${SPACE_WARN_GB:-9.5}GB of the 12GB"
    echo "Free-edition limit. Run './local-26ai.sh used-space' for the detail."
    echo ""
    ;;
  0) ;;
  *)
    echo "Note: could not read the database space usage. Continuing to shut down."
    ;;
esac

echo "Gracefully stopping Oracle Database"
$CONTAINER_CLI exec $CONTAINER_NAME bash -c "echo 'shutdown immediate;
exit' | sqlplus / as sysdba && exit"

echo "Stopping Containers"
$DOCKER_COMPOSE -f docker-compose.yml stop
