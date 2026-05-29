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

# Detect docker compose command (prefer v2 plugin, fall back to standalone v1)
if docker compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
else
  echo "Error: neither 'docker compose' nor 'docker-compose' found"
  exit 1
fi
