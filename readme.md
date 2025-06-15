# Containerized APEX Development Environment

**Have a 23ai with APEX and ORDS running in a few minutes**

[Migration Guide](./docs/migrations/readme.md)

## What is this?

This set of scripts aims to make developing APEX on your local machine as easy as possible. It is a ready-to-use setup with common tasks automated as bash scripts.

- Create users and workspaces with optimal settings with a single command
- All users are stored for easy access with SQLcl or VS Code SQL Developer
- Easily delete all data to test installation scripts multiple times
- Backup and restore your data, workspaces and apps
- Run ORDS with SSL
- Test APEX application installs

**This is not for production use!** I configured the environment to be unsecure to make development as easy as possible. I also run some statements that are not supported and could be dangerous. So use this at your own risk and run backups regularly.

## Pre-requisites

- Docker or Podman or any other docker compatible container runtime
  - Make sure your virtual machine has enough resources allocated. **The default Podman VM will cause issues with Oracle**. I recommend at least 4GB of RAM and 3 CPUs. [Find out more here](https://hartenfeller.dev/blog/oracle-23ai-container-wont-start-mac).
- docker-compose / podman-compose
- SQLcl + "sql" command in PATH
- Bash compatible shell (I recommend using WSL2 on Windows)

### On mac?

[Read this](./docs/podman-on-mac.md) for more information.

## Setup

- Clone this repository
- Start a terminal in the cloned directory
- Run this (change docker-compose to podman-compose if you use podman):

```sh
# setup the environment
./setup.sh

# start the containers
docker-compose up -d

# wait for ORDS to install APEX
docker logs --follow local-ords
# INFO : This container will start a service running ORDS 24.4.0 and APEX 24.1.0.
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

# !IMPORTANT
# If you see APEX as unavailable at ther landing page (http://localhost:8181/ords/_/landing)
# and the ords logs show that the config folder is not writable, you need to run the following command:
# chmod -R 777 ./ords-config
#
# then restart the container: docker-compose restart ords

# Run DB config script:
./scripts/after-first-db-start.sh
```

Make sure you permission to run the scripts. If you get errors, run the following command:

```sh
chmod +x ./local-23ai.sh ./setup.sh ./scripts/*.sh
```

> [!IMPORTANT]  
> If you are having issues with ORDS saying it can't connect to the database, please downgrade it to 24.3 in the docker-compose.yml. Weirdly, this issue only happens in some cases.


> [!IMPORTANT]  
> Currently ORDS installs APEX 24.1. Follow [this guide](https://github.com/United-Codes/uc-local-apex-dev/blob/25-1/docs/migrations/25-1.md#upgrade-apex-to-242) on how to upgrade to 24.2.

### Optional: SSL

If you want to use SSL (https) run the following command:

```sh
sudo ./scripts/create-self-signed-certificates.sh
docker-compose restart ords
```

Now you can access ORDS **only** with HTTPS: https://localhost:8181/ords/_/landing.

The script will create a self-signed certificate and store it in your operating system's keychain. It is valid for 9999 days so you don't have to worry about renewing it.

Note that I only tested this on macOS. It should work on Linux as well, but if you have issues please modify the script and create a pull request.

## Stopping the containers

The containers will use some resources in the background. You can stop them with the following command:

```sh
docker-compose stop
# or if you set up the path (see below)
local-23ai.sh stop
```

## APEX

You can access any workspace with following credentials:

URL: http://localhost:8181/ords/apex
Username: admin
Password: Welcome_1

### Adding new workspace

See [create user](#create-user-and-workspace) section.

## Common tasks


Add the cloned git repository to your PATH in your `.zshrc`.

```sh 
export PATH="/Users/phartenfeller/Documents/Docker/apex-24-1:$PATH"
```

Now you can call any script from anywhere.

```sh
local-23ai.sh backup-all
```

### Create user and workspace

This command will create a new db schema and workspace. You can access the workspace with both the username `ADMIN` or the given schema name and the password `Welcome_1`.

```sh
local-23ai.sh create-user movies
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
  - Sets convenient settings like max session idle time to 7 days 

### Clear a schema

This is useful if you want to test install scripts multiple times. It will drop all objects in the schema.

```sh
local-23ai.sh clear-schema {schema_name}
# it will ask for confirmation
```

From experience: never run it accidentally on sys :).

### Drop a schema

This will drop the schema and all objects in it. It will also remove the user from the database.

```sh
local-23ai.sh drop-user {schema_name}
```

### Using the VS Code SQL Developer debugger

You can use the VS Code SQL Developer extension to debug your PL/SQL code. Any created user has the necessary grants to use the debugger.

- Compile your package for debug
- Set a breakpoint
- Start the debugger
- Pass your local machine IP
  - Get that with `ipconfig getifaddr en0`

### Backup

#### Backup all users

This will create a datapump dump of all users. If there is an APEX workspace it will backup both the workspace defintion and the applications in them.

```sh
local-23ai.sh backup-all
```


#### Backup a specific schema

This will create a datapump dump of the database schema. If there is an APEX workspace it will backup both the workspace defintion and the applications in it.

The files are written to the `./backups/export` directory.

```sh
local-23ai.sh backup-schema {schema_name}
```

### Import Backup

You can currently run `local-23ai.sh import-backup <schema-name>` to import a backup. Currently it does only create the user if it does not exist and import the data pump dump.

In the future I want to add the possibility to import APEX workspaces and applications. Currently I need to future out:
- What if the workspace already exists?
- What if an application with this ID already exists?

### Test APEX application installs

This script will install an application into the `UC_TESTINSTALL_1` schema + worskspace. It will also create a new schema and workspace if they do not exist or clear them if they do. As a result you will get:

- A list with object types and counts
- A list with invalid objects
- A scan result of the APEX object dependency scanner

```sh
local-23ai.sh test-app-insall ./path/to/my_app.sql
```

## Delete all database data

If you want to delete your current database (everything will be lost), you can run the following command:

```sh
docker-compose down
docker volume rm oradata
rm .env
```

If you follow the [setup](#setup) instructions again, you will have a fresh database.



## Contributing

If you have any ideas on how to improve this setup, please create an issue or a pull request.

I am especially thankful for improvements to the bash scripts.

## Troubleshooting

...soon


## Special thanks

- The [contributors](https://github.com/United-Codes/uc-local-apex-dev/graphs/contributors) for their help
- Tim Hall for the [drop_all.sql](https://oracle-base.com/dba/script?category=miscellaneous&file=drop_all.sql) script
- Philipp Salvisberg for [helping me to figure out how to use the debugger](https://gist.github.com/PhilippSalvisberg/2f2853bc7a95fa86d9de9c0deab10602)
- Scott Spendolini for his blog post on [how to add self-signed certificates to ORDS](https://spendolini.blog/adding-ssl-to-your-ords-container)
- The database team for providing an ARM image for the Oracle database
- The ORDS team for providing an ARM image for ORDS

The cherry on top would be Oracle making APEX patches free to download for everyone.
