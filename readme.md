# Oracle APEX Docker

## What is this?

This set of scripts aims to make developing APEX on your local machine as easy as possible. It is a ready-to-use setup with common tasks automated as bash scripts.

- Have a 23ai with APEX and ORDS running in ~3 minutes
- Create users and workspaces with optimal settings with a single command
- All users are stored for easy access with SQLcl or VS Code SQL Developer
- Easily delete all data to test installation scripts multiple times
- Backup and restore your data, workspaces and apps

## Pre-requisites

- Docker or Podman or any other docker compatible container runtime
  - Make sure your virtual machine has enough resources allocated. **The default Podman VM will cause issues with Oracle**. I recommend at least 4GB of RAM and 3 CPUs. [Find out more here](https://hartenfeller.dev/blog/oracle-23ai-container-wont-start-mac).
- docker-compose
- SQLcl + "sql" command in PATH
- Bash compatible shell (I recommend using WSL2 on Windows)

### On mac?

```sh
brew install docker docker-compose podman sqlcl
```

And [read this](https://hartenfeller.dev/blog/sqlcl-homebrew-macos) on how to make SQLcl work fine after updates.

## Setup

- Clone this repository
- Start a terminal in the cloned directory
- Run this:

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

Make sure you permission to run the scripts. If you get errors, run the following command:

```sh
chmod +x ./setup.sh ./scripts/*.sh
```

## Stopping the containers

The containers will use some resources in the background. You can stop them with the following command:

```sh
docker-compose stop
```

## APEX

You can access any workspace with following credentials:

URL: http://localhost:8181/ords/apex
Username: admin
Password: Welcome_1

### Adding new workspace

See [create user](#create-user-and-workspace) section.

## Common tasks

**Run all scripts from the root directory of this repository.** Like `./scripts/...`.

It can help to set up an alias to quickly cd into the directory:

```sh
alias apex-docker='cd /path/to/cloned-repo'
```

### Create user and workspace

This command will create a new db schema and workspace. You can access the workspace with both the username `ADMIN` or the given schema name and the password `Welcome_1`.

``` sh
./scripts/create-user.sh movies
```

If you don't want to create a workspace, you can add the `--skip_workspace` flag.

The script will do the following:

- Create a new schema with the given name
- Store the schema password in the .env file
- Save the connection with password in the connection store
  - Easy access with SQLcl or VS Code SQL Developer
  - Example sqlcl: `sql -name local-23ai-{schema_name}`
- Add all developing necessary grants to the schema
- Gives access to the datapump directories
- Create a new workspace with the schema name
  - Sets convinient settings like max session idle time to 7 days 

### Clear a schema

This is useful if you want to test install scripts multiple times. It will drop all objects in the schema.

``` sh
./scripts/clear-schema.sh {schema_name}
# it will ask for confirmation
```

From experience: never run it accidentally on sys :).

### Using the VS Code SQL Developer debugger

You can use the VS Code SQL Developer extension to debug your PL/SQL code. Any created user has the necessary grants to use the debugger.

- Compile your package for debug
- Set a breakpoint
- Start the debugger
- Pass your local machine IP
  - Get that with `ipconfig getifaddr en0`

### Backup

#### Backup a specific schema

This will create a datapump dump of the database schema. If there is an APEX workspace it will backup both the workspace defintion and the applications in it.

The files are written to the `./backups/export` directory.

``` sh
./scripts/backup-schema.sh {schema_name}
```

## Delete database data

If you want to delete your current databse (everything will be lost), you can run the following command:

```sh
docker-compose down
docker volume rm oradata
rm .env
```

If you follow the [setup](#setup) instructions again, you will have a fresh database.


## FAQ

### Can I modify ORDS settings?

Yes. A folder named `ords-config` will be created in the root directory. You can modify the config files there. The changes will be applied on the next restart of the ORDS container.

## Troubleshooting

...soon


## Special thanks

- Tim Hall for the [drop_all.sql](https://oracle-base.com/dba/script?category=miscellaneous&file=drop_all.sql) script
- Philipp Salvisberg for [helping me to figure out how to use the debugger](https://gist.github.com/PhilippSalvisberg/2f2853bc7a95fa86d9de9c0deab10602)
- The database team for providing an ARM image for the Oracle database
- The ORDS team for providing an ARM image for ORDS

The cherry on top would be Oracle making APEX patches free to download for everyone.
