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
# SECURE_MODE is this project's own hardening flag (see install.sh --secure).
# Deliberately NOT named FORCE_SECURE: the Oracle ORDS image reads FORCE_SECURE
# from this shared env_file and would refuse to boot without TLS certs.
echo "SECURE_MODE=\"false\"" >>.env
# ORDS debug-to-screen (maps to the container's DEBUG env in docker-compose.yml).
# Default on for dev; install.sh --secure flips it to false. NOT named ORDS_DEBUG:
# that is a reserved variable inside the ORDS image's `ords` launcher (it holds
# JVM -agentlib:jdwp options) and setting it here breaks the ORDS install.
echo "DEBUG_TO_SCREEN=\"true\"" >>.env

echo "Created .env file"

# create bind-mount dirs if not exists. chmod 777 so the ORDS container's mapped
# user can write them under rootless podman.
if [ ! -d ./ords-config ]; then
  mkdir ./ords-config
  chmod 777 ./ords-config
fi
if [ ! -d ./apex-images ]; then
  mkdir ./apex-images
  chmod 777 ./apex-images
fi

mkdir -p ./backups/export
mkdir -p ./backups/import
