#!/bin/bash

set -e

# Store the location of this index script to find other scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Print one command with its "# desc:" line from the script header
print_command() {
  local name="$1"
  local desc
  desc=$(grep -m1 '^# desc:' "$SCRIPT_DIR/scripts/$name.sh" 2>/dev/null | sed 's/^# desc: //')
  printf "  %-36s %s\n" "$name" "$desc"
}

print_help() {
  echo "Usage: local-26ai.sh <command> [arguments]"
  echo
  echo "Containers:"
  for cmd in start stop; do print_command "$cmd"; done
  echo
  echo "Users & Workspaces:"
  for cmd in create-user clear-schema drop-user; do print_command "$cmd"; done
  echo
  echo "Backups & Import:"
  for cmd in backup-all backup-user import-backup import-datapump import-all sync-backups-folder fix-ws-group-ids; do print_command "$cmd"; done
  echo
  echo "Testing:"
  for cmd in test-app-install test-script-install; do print_command "$cmd"; done
  echo
  echo "Disk Space:"
  for cmd in used-space shrink-space compress-space; do print_command "$cmd"; done
  echo
  echo "Setup & Maintenance:"
  for cmd in after-first-db-start upgrade-apex unexpire-accounts disable-password-expiration disable-archive-logs create-self-signed-certificates install-dbms-cloud; do print_command "$cmd"; done
  echo
  echo "Docs: https://www.united-codes.com/products/uc-local-apex-dev/docs/"
}

# The first argument will be the script name
script_name="$1"

if [ -z "$script_name" ] || [ "$script_name" = "--help" ] || [ "$script_name" = "-h" ] || [ "$script_name" = "help" ]; then
  print_help
  exit 0
fi

# Remove the first argument, shifting all other arguments left
shift

export ORIGINAL_PWD="$PWD"

# Check if script exists
if [ -f "$SCRIPT_DIR/scripts/$script_name.sh" ]; then
  # Change to the script's directory before execution
  # This ensures relative paths within the script work correctly
  cd "$SCRIPT_DIR"
  # Execute the script with any additional arguments
  ./scripts/"$script_name".sh "$@"
else
  echo "Command '$script_name' not found."
  echo
  print_help
  exit 1
fi
