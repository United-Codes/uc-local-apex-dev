#!/usr/bin/env bash
# desc: DataPump-export all schemas incl. APEX workspaces, apps and ORDS modules

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/read_user_names.sh

read -r -a db_users <<<"$(get_user_names)"

if [ ${#db_users[@]} -eq 0 ]; then
  echo "No <NAME>_USER_PASSWORD entries found in .env - nothing to back up"
  exit 0
fi

echo "Backing up ${#db_users[@]} schema(s): ${db_users[*]}"
echo ""

ok_users=()
failed_users=()

for user in "${db_users[@]}"; do
  echo "========================================"
  echo "Backing up $user"
  echo "========================================"
  if ./scripts/backup-user.sh "$user"; then
    ok_users+=("$user")
  else
    echo "!! backup failed for $user"
    failed_users+=("$user")
  fi
  echo ""
done

echo "========================================"
echo "Backup Summary"
echo "========================================"
echo "Total schemas:  ${#db_users[@]}"
echo "Backed up:      ${#ok_users[@]}"
echo "Failed:         ${#failed_users[@]}"

if [ ${#failed_users[@]} -gt 0 ]; then
  echo ""
  echo "Failed schemas:"
  for user in "${failed_users[@]}"; do
    echo "  - $user"
  done
  # A backup run that lost schemas must not look like a success to cron or CI.
  exit 1
fi

echo ""
echo "All schemas backed up to ./backups/export"
