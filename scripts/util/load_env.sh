#!/usr/bin/env bash

if [ ! -f .env ]; then
  echo "Error: env file not found"
  exit 1
fi

# check if .env is in the current directory or in the parent directory
export $(grep -v '^#' .env | xargs)

echo "loaded .env file"

# Detect docker compose command (standalone vs plugin)
if command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
elif docker compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE="docker compose"
else
  echo "Error: neither 'docker-compose' nor 'docker compose' found"
  exit 1
fi
