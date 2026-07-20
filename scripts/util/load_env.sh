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

# Detect container engine (honor a pre-set CONTAINER_CLI, else prefer docker, fall back to podman)
if [ -n "${CONTAINER_CLI:-}" ]; then
  :
elif command -v docker &>/dev/null; then
  CONTAINER_CLI="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_CLI="podman"
else
  echo "Error: neither 'docker' nor 'podman' found"
  exit 1
fi

# Detect its compose command. ONLY the native '<engine> compose' subcommand is
# supported -- the standalone 'docker-compose' / 'podman-compose' tools are not.
if $CONTAINER_CLI compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE="$CONTAINER_CLI compose"
else
  # shellcheck source=scripts/util/compose-hint.sh
  source "$(dirname "${BASH_SOURCE[0]}")/compose-hint.sh"
  compose_install_hint "$CONTAINER_CLI"
  exit 1
fi

export CONTAINER_CLI DOCKER_COMPOSE
