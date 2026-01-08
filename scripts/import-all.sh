#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

echo "Scanning .env file for user password entries..."

# Read .env file and extract all non-commented *_USER_PASSWORD entries
USER_PASSWORDS=$(grep -E "^[A-Z0-9_]+_USER_PASSWORD=" .env | grep -v "^#")

if [ -z "$USER_PASSWORDS" ]; then
  echo "No user password entries found in .env file"
  exit 0
fi

# Extract usernames and store in array
USERNAMES=()
while IFS= read -r line; do
  # Extract the username part (everything before _USER_PASSWORD=)
  USERNAME=$(echo "$line" | sed -E 's/^([^=]+)_USER_PASSWORD=.*/\1/')
  USERNAMES+=("$USERNAME")
done <<< "$USER_PASSWORDS"

echo "Found ${#USERNAMES[@]} users to import:"
for user in "${USERNAMES[@]}"; do
  echo "  - $user"
done

echo ""
read -p "Do you want to import all these users? (y/n) " answer

if [[ $answer != "y" ]] && [[ $answer != "Y" ]]; then
  echo "Stopping..."
  exit 0
fi

echo ""
echo "Starting import process..."
echo ""

# Import each user
SUCCESSFUL=0
FAILED=0
FAILED_USERS=()

for USERNAME in "${USERNAMES[@]}"; do
  echo "========================================"
  echo "Importing user: $USERNAME"
  echo "========================================"
  
  if ./scripts/import-backup.sh "$USERNAME" -y; then
    echo "✓ Successfully imported $USERNAME"
    ((SUCCESSFUL++))
  else
    echo "✗ Failed to import $USERNAME"
    ((FAILED++))
    FAILED_USERS+=("$USERNAME")
  fi
  
  echo ""
done

echo "========================================"
echo "Import Summary"
echo "========================================"
echo "Total users: ${#USERNAMES[@]}"
echo "Successfully imported: $SUCCESSFUL"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
  echo ""
  echo "Failed users:"
  for user in "${FAILED_USERS[@]}"; do
    echo "  - $user"
  done
  exit 1
fi

echo ""
echo "All users imported successfully!"
