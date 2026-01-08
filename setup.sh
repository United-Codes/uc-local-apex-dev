#!/bin/bash
PRINT_RED='\033[0;31m'
PRINT_RESET='\033[0m'

source ./scripts/util/generate_password.sh

# generate sys password
SYS_PASSWORD=$(generate_password)

# if .env exsits, rename to .env.bak
if [ -f .env ]; then
  mv .env .env.bak
fi

# write .env file with passwords
echo "ORACLE_PASSWORD=\"$SYS_PASSWORD\"" >.env
echo "ORACLE_PWD=\"$SYS_PASSWORD\"" >>.env
#echo "APP_USER=\"$APP_USER\"" >>.env
#echo "APP_USER_PASSWORD=\"$APP_USER_PASSWORD\"" >>.env
echo "DB_CONN_BASE=local-26ai" >>.env
echo "DB_CONN_NAME=local-26ai-sys" >>.env
echo "CONTAINER_NAME=local-26ai" >>.env
echo "DBSERVICENAME=\"FREEPDB1\"" >>.env
echo "DBHOST=\"26ai\"" >>.env
echo "DBPORT=\"1521\"" >>.env
echo "FORCE_SECURE=\"false\"" >>.env

echo "Created .env file"

# create ords-config directory if not exists
if [ ! -d ./ords-config ]; then
  mkdir ./ords-config
  chmod 777 ./ords-config
fi

mkdir -p ./backups/export
mkdir -p ./backups/import
