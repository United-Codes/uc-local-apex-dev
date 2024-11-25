set -e

source ./scripts/util/load_env.sh

# check parameter is passed
if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name>"
  exit 1
fi

USERNAME=$1
USERNAME_UPPER=$(echo $USERNAME | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo $USERNAME | tr '[:upper:]' '[:lower:]')
SQLCRED_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

sql -name $SQLCRED_NAME <<SQL
  datapump import -
  -schemas ${USERNAME_LOWER} -
  -directory datapump_import_dir -
  -dumpfile ${USERNAME_LOWER}.dmp -
  -logfile ${USERNAME_LOWER}.log -
  -version latest

  datapump import -
  -schemas ${USERNAME_LOWER} -
  -directory datapump_import_dir -
  -dumpfile ${USERNAME_LOWER}.dmp -
  -logfile ${USERNAME_LOWER}.log -
  -version latest

  commit;

  exit;
SQL
