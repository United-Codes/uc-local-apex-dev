#!/usr/bin/env bash
# desc: Gracefully shut down the database, then stop the containers

set -e

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

case "$space_rc" in
  11)
    echo ""
    echo "!! CRITICAL: the database is close to the 12GB Free-edition limit."
    echo "!! If it grows past 12GB it will NOT open again, in any mode, and it"
    echo "!! cannot be repaired from inside. Before you fill it further, run:"
    echo "!!     ./local-26ai.sh shrink-space"
    echo "!!     ./local-26ai.sh cap-tablespaces --apply"
    echo ""
    ;;
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
