# Oracle APEX Docker

## Setup

You need to run the following commands to setup the environment.

```sh
# setup the environment
./setup.sh

# start the containers
docker-compose up -d

# wait for ORDS to install APEX
docker logs --follow local-ords
# INFO : This container will start a service running ORDS 24.3.1 and APEX 24.1.0.
# INFO : CONN_STRING has been found in the container variables file.
# INFO : Database connection established.
# INFO : Apex is not installed on your database.
# INFO : Installing APEX on your DB please be patient.

# wait for:
# INFO : APEX has been installed.
# INFO : Configuring APEX.
# INFO : APEX_PUBLIC_USER has been configured as oracle.
# INFO : APEX ADMIN password has configured as 'Welcome_1'.
# INFO : Use below login credentials to first time login to APEX service:
#         Workspace: internal
#         User:      ADMIN
#         Password:  Welcome_1


# Run DB config script:
./scripts/after-first-db-start.sh
```

Make sure you permission to run the scripts. If not, run the following command:

```sh
chmod +x ./setup.sh ./scripts/*.sh
```

## APEX

You can access any workspace with following credentials:

URL: http://localhost:8181/ords/apex
Username: admin
Password: Welcome_1

### Adding new workspace

This command will create a new db schema and workspace. You can access the workspace with both the username `ADMIN` or the given schema name and the password `Welcome_1`.

``` sh
./scripts/create-user.sh movies
```

## Delete database data

```sh
docker-compose down
docker volume rm oradata
```


## Troubleshooting

