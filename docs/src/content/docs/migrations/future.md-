# Migrate to 25.1 

Because the database files don't let us just change the version number and start the database, we need to do a backup and restore. To make sure that these steps happen we use different branches for each version. This way you can't just accidentally start the database with the wrong version by just pulling the latest changes.

**Carefully follow the steps below. You could loose data if you fail to.**

## Check that db is running

```sh
docker ps 
```

Otherwise start the database.

## Switch branch

```sh
git checkout 25-1
```

## Give permission to all new scripts

```sh
chmod +x ./local-23ai.sh ./setup.sh ./scripts/*.sh
```

## Backup the database

This will backup all schemas and APEX workspaces that where created with the `local-23ai.sh create-user` script. If you have additional schemas or workspaces **you need to backup them manually**.

```sh
local-23ai.sh backup-all   
```

Now check the `backups/export` directory if the backup was created successfully.

## Backup the oradata volume

Note this can take a moment. Make sure that `./backups/oradata` does not exist.

```sh
source ./scripts/util/load_env.sh

docker exec $CONTAINER_NAME bash -c "echo 'shutdown immediate;
exit' | sqlplus / as sysdba && exit"

docker cp $CONTAINER_NAME:/opt/oracle/oradata ./backups/oradata
```

## Stop the containers

```sh
local-23ai.sh stop
```

## Remove the oradata volume

As we need to create a scratch database and want to just import all the data again, we need to remove the old oradata volume.

```sh
docker volume rm oradata
```

## Create new conn string

```sh
source ./scripts/util/load_env.sh
echo "CONN_STRING=sys/$ORACLE_PASSWORD@23ai:1521/FREEPDB1" >./ords-secrets/conn_string.txt

...

- docker-compose up -d
- after first start script
- import data
