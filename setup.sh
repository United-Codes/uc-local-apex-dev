#!/bin/zsh
PRINT_RED='\033[0;31m'
PRINT_RESET='\033[0m'

source ./scripts/util/generate_password.sh

# generate sys password
SYS_PASSWORD=$(generate_password)
APP_USER="APP_USER"
APP_USER_PASSWORD=$(generate_password)

# if .env exsits, rename to .env.bak
if [ -f .env ]; then
  mv .env .env.bak
fi

# write .env file with passwords
echo "#ORACLE_PASSWORD = SYS_PASSWORD" >.env
echo "ORACLE_PASSWORD=\"$SYS_PASSWORD\"" >>.env
echo "ORACLE_PWD=\"$SYS_PASSWORD\"" >>.env
echo "APP_USER=\"$APP_USER\"" >>.env
echo "APP_USER_PASSWORD=\"$APP_USER_PASSWORD\"" >>.env
echo "DB_CONN_BASE=local-23ai" >>.env
echo "DB_CONN_NAME=local-23ai-sys" >>.env
echo "CONTAINER_NAME=apex-24-1-23ai" >>.env

echo "Password written to .env file"

# create ords-secrets directory if not exists
if [ ! -d ./ords-secrets ]; then
  mkdir ./ords-secrets
fi

# remove conn_string.txt if exists
if [ -f ./ords-secrets/conn_string.txt ]; then
  rm ./ords-secrets/conn_string.txt
fi

# create ords-config directory if not exists
if [ ! -d ./ords-config ]; then
  mkdir ./ords-config
fi

# write conn_string.txt file with connection string
echo "CONN_STRING=sys/$SYS_PASSWORD@23ai:1521/FREEPDB1" >./ords-secrets/conn_string.txt

echo "credentails created"

mkdir -p ./backups/export
mkdir -p ./backups/import
