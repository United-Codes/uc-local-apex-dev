---
title: Init podman on MacOS
description: Getting started with Podman on macOS for Oracle 26ai development
sidebar:
    order: 10
---

## Prerequisites

You need the [homebrew](https://brew.sh/) package manager for this:

```sh
brew install sqlcl

# Optional: only if you want to use the docker CLI
# against Podman's Docker-compatible socket
brew install docker docker-compose
```

Upgrade tolerant way of adding SQLcl to your PATH (add it to your ~/.bashrc or ~/.zshrc):

```sh
SQLCLPATH=$(ls -t $(brew --prefix)/Caskroom/sqlcl | head -1)
PATH=$(brew --prefix)/Caskroom/sqlcl/$SQLCLPATH/sqlcl/bin:$PATH
```

[Read this](https://hartenfeller.dev/blog/sqlcl-homebrew-macos) for more information.

## Installing Podman

If you have no Docker runtime yet, I recommend doing the following:

```sh
brew install podman

podman machine init

# I recommend increasing the resources if you have enough
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

Now test that podman works:

```sh
podman ps
```

The project's scripts (`install.sh`, `local-26ai.sh`, etc.) natively detect Podman — if `docker`
isn't installed they automatically use `podman` and the native `podman compose` subcommand. You can
run them as-is. If you have both Docker and Podman installed and want to force Podman, set
`CONTAINER_CLI`:

```sh
CONTAINER_CLI=podman ./install.sh
```

If you'd rather route the scripts' `docker` usage through Podman's Docker-compatible socket instead,
you can still do that — test it with `docker ps`.

## Troubleshooting

If this does not work please [follow this guide](https://podman-desktop.io/docs/migrating-from-docker/using-the-docker_host-environment-variable).

If you have this file `~/.docker/config.json`, delete or rename it if you see this error: `error getting credentials - err: exec: "docker-credential-desktop": executable file not found in $PATH`.

Alternatively, you can drive the stack directly with the native `podman compose` subcommand:

```sh
podman compose up -d
podman compose stop
podman ps
# etc
```

Use `podman compose` (the subcommand), not the standalone `podman-compose` package — the latter
can cause trouble and doesn't support everything in this project's `docker-compose.yml`.

## After a restart

After a restart of your Mac, you need to start the Podman machine again:

```sh
podman machine start
```

Equally you can stop it with:

```sh
podman machine stop
```

But I recommend stopping the database before stopping the Podman machine:

```sh
local-26ai.sh stop
```
