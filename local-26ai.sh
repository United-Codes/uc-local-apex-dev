#!/bin/bash

set -e

# Store the location of this index script to find other scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The first argument will be the script name
script_name="$1"
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
  echo "Script '$script_name' not found in $SCRIPT_DIR"
  echo "Available scripts:"
  ls -1p "$SCRIPT_DIR/scripts" | grep -v /
fi
