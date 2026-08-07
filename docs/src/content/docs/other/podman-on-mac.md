---
title: Init podman on MacOS
description: Getting started with Podman on macOS for Oracle 26ai development
sidebar:
    order: 10
---

## Prerequisites

You need the [homebrew](https://brew.sh/) package manager for these steps:

```sh
brew install sqlcl

# Optional: only if you want to use the docker CLI
# against Podman's Docker-compatible socket
brew install docker docker-compose
```

Add SQLcl to your `PATH` with these lines. They also work after an upgrade of SQLcl. Put them in your `~/.bashrc` or `~/.zshrc`:

```sh
SQLCLPATH=$(ls -t $(brew --prefix)/Caskroom/sqlcl | head -1)
PATH=$(brew --prefix)/Caskroom/sqlcl/$SQLCLPATH/sqlcl/bin:$PATH
```

[Read this](https://hartenfeller.dev/blog/sqlcl-homebrew-macos) for more information.

## Installing Podman

If you have no Docker runtime yet, run these commands:

```sh
brew install podman

podman machine init

# Increase the memory and the CPUs if the host has enough
podman machine set --memory 4096
podman machine set --cpus 3

podman machine start

# if it says something like:

# The system helper service is not installed; the default Docker API socket
# address can’t be used by podman. If you would like to install it, run the following commands:
# sudo /opt/homebrew/Cellar/podman/5.3.1/bin/podman-mac-helper install
# podman machine stop; podman machine start

# Please do so
```

Now make sure that podman works:

```sh
podman ps
```

The scripts of this project (`install.sh`, `local-26ai.sh`, and the scripts in `./scripts`) detect
Podman. If `docker` is not installed, they use `podman` and the native `podman compose` subcommand.
You can run them without a change. If both Docker and Podman are installed, set `CONTAINER_CLI` to
select Podman:

```sh
CONTAINER_CLI=podman ./install.sh
```

You can also send the `docker` commands of the scripts to the Docker-compatible socket of Podman.
Make sure that this works with `docker ps`.

## Troubleshooting

If this does not work, [read this guide](https://podman-desktop.io/docs/migrating-from-docker/using-the-docker_host-environment-variable).

If you see this error, delete or rename the `~/.docker/config.json` file: `error getting credentials - err: exec: "docker-credential-desktop": executable file not found in $PATH`.

You can also control the stack directly with the native `podman compose` subcommand:

```sh
podman compose up -d
podman compose stop
podman ps
# etc
```

Use the `podman compose` subcommand, not the standalone `podman-compose` package. That package does
not support everything in the `docker-compose.yml` file of this project.

## After a restart

After a restart of your Mac, start the Podman machine again:

```sh
podman machine start
```

You can stop it with this command:

```sh
podman machine stop
```

Stop the database before you stop the Podman machine:

```sh
local-26ai.sh stop
```
