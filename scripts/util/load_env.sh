#!/usr/bin/env bash

if [ ! -f .env ]; then
  echo "Error: env file not found"
  exit 1
fi

# check if .env is in the current directory or in the parent directory
export $(grep -v '^#' .env | xargs)

echo "loaded .env file"

# Wrap SQLcl so non-interactive (heredoc/pipe) calls don't fail with
# "Unable to create a terminal". JLine can't allocate a real terminal when
# stdin isn't a TTY (varies by SQLcl/JLine version); TERM=dumb makes it fall
# back silently. Interactive sessions keep their real TERM so line editing,
# history and colors still work.
sql() {
  if [ -t 0 ]; then
    command sql "$@"
  else
    TERM=dumb command sql "$@"
  fi
}
export -f sql

# Detect container engine + its Compose plugin together. ONLY the native
# '<engine> compose' subcommand is supported -- the standalone 'docker-compose'
# / 'podman-compose' tools are not.
#
# An engine is only usable if it ALSO provides a working 'compose' subcommand.
# A host may have the docker CLI without the Compose plugin while podman ships a
# working 'podman compose' (or vice versa) -- so we prefer docker, fall back to
# podman, but pick the first candidate that has BOTH the CLI and compose.
has_compose() { "$1" compose version &>/dev/null; }

if [ -n "${CONTAINER_CLI:-}" ]; then
  candidates=("$CONTAINER_CLI")
else
  candidates=()
  command -v docker &>/dev/null && candidates+=("docker")
  command -v podman &>/dev/null && candidates+=("podman")
fi

if [ ${#candidates[@]} -eq 0 ]; then
  echo "Error: neither 'docker' nor 'podman' found"
  exit 1
fi

DOCKER_COMPOSE=""
for engine in "${candidates[@]}"; do
  if has_compose "$engine"; then
    CONTAINER_CLI="$engine"
    DOCKER_COMPOSE="$engine compose"
    break
  fi
done

if [ -z "$DOCKER_COMPOSE" ]; then
  # No candidate has a working Compose plugin -- report against the engine we
  # would otherwise have chosen (the first candidate) and bail.
  CONTAINER_CLI="${candidates[0]}"
  # shellcheck source=scripts/util/compose-hint.sh
  source "$(dirname "${BASH_SOURCE[0]}")/compose-hint.sh"
  compose_install_hint "$CONTAINER_CLI"
  exit 1
fi

export CONTAINER_CLI DOCKER_COMPOSE
