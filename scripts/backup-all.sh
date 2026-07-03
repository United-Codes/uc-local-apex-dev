set -e
# desc: DataPump-export all schemas incl. APEX workspaces, apps and ORDS modules

source ./scripts/util/load_env.sh
source ./scripts/util/read_user_names.sh

read -a db_users <<<"$(get_user_names)"

for user in "${db_users[@]}"; do
  echo "Backing up $user"
  ./scripts/backup-user.sh "$user" || true
done

./scripts/sync-backups-folder.sh
