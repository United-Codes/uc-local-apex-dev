# Init podman on MacOS

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

If you have no docker runtime yet I recommend doing the following:

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

If this does not work, please let me know if and how you fixed the issue.

Alternatively you can also use `podman` commands like:

```sh
podman-compose up -d
podman-compose stop
podman ps
# etc
```
