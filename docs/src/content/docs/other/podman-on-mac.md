---
title: Init podman on MacOS
description: Getting started with Podman on macOS for Oracle 23ai development
sidebar:
    order: 10
---

## Prerequisites

You need the [homebrew](https://brew.sh/) package manager for this:

```sh
brew install docker docker-compose sqlcl
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

Now test if you can run podman via the docker command:

```sh
docker ps
```

## Troubleshooting

If this does not work please [follow this guide](https://podman-desktop.io/docs/migrating-from-docker/using-the-docker_host-environment-variable).

If you have this file `~/.docker/config.json`, delete or rename it if you see this error: `error getting credentials - err: exec: "docker-credential-desktop": executable file not found in $PATH`.

Alternatively, you can try using `podman` commands like:

```sh
podman-compose up -d
podman-compose stop
podman ps
# etc
```
But podman-compose can cause some trouble in my experience.

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
local-23ai.sh stop
```
