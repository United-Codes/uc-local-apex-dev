set -e

source ./scripts/util/load_env.sh
source ./scripts/util/read_user_names.sh

read -a db_users <<<"$(get_user_names)"

for user in "${db_users[@]}"; do
  echo "Backing up $user"
  ./scripts/backup-user.sh $user
done
