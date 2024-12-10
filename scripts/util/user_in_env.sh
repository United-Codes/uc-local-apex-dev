#!/usr/bin/env bash

user_in_env() {
  if [ -z "$1" ]; then
    echo "Usage: user_in_env USERNAME"
    exit 1
  fi

  USERNAME=$1
  USERNAME_UPPER=$(echo $USERNAME | tr '[:lower:]' '[:upper:]')
  USERNAME_ENTRY="${USERNAME_UPPER}_USER_PASSWORD"

  env_file=".env"

  if [ ! -f "$env_file" ]; then
    echo "Error: $env_file file not found"
    exit 1
  fi

  if ! grep -q "^$USERNAME_ENTRY=" "$env_file"; then
    echo "Error: $USERNAME_UPPER ($USERNAME_ENTRY) not found in $env_file"
    exit 1
  fi
}
