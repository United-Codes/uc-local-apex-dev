#!/usr/bin/env bash
# desc: DataPump-export all schemas incl. APEX workspaces, apps and ORDS modules

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/read_user_names.sh

# Step 0: look at the database. export-gaps writes recovery/schemas.tsv (every
# schema of ours, also the ones that are not in .env), the SQL for what a schema
# export does not carry, and the list of things that nobody can restore.
RECOVERY_DIR="./backups/export/recovery"
db_users=()
GAPS_FAILED=false
if ./scripts/export-gaps.sh; then
  while IFS='|' read -r name _; do
    [ -n "$name" ] && db_users+=("$name")
  done <"$RECOVERY_DIR/schemas.tsv"
else
  echo "!! export-gaps failed. Backing up only the schemas in .env, without the recovery files."
  GAPS_FAILED=true
  read -r -a db_users <<<"$(get_user_names)"
fi

if [ ${#db_users[@]} -eq 0 ]; then
  echo "No schemas found - nothing to back up"
  exit 0
fi

echo ""
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

# Without export-gaps the recovery files are missing or from an earlier run, and
# schemas that are not in .env have no dump. rebuild must not delete anything then.
if [ "$GAPS_FAILED" = true ]; then
  echo ""
  echo "!! export-gaps failed. The files in $RECOVERY_DIR are not from this run."
  exit 1
fi

echo ""
echo "All schemas backed up to ./backups/export"

if grep -q '[^[:space:]]' "$RECOVERY_DIR/unrecoverable.txt"; then
  echo ""
  echo "Reminder: no backup holds these. Enter or create them again after a restore:"
  grep -v '^[[:space:]]*$' "$RECOVERY_DIR/unrecoverable.txt" | sed 's/^/  - /'
fi
