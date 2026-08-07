#!/usr/bin/env bash
#
# compose_install_hint <engine>
#
# Print guidance on how to obtain the Compose plugin (the native
# '<engine> compose' subcommand) for the given container engine, tailored to the
# host OS/distro when we can detect it. Everything goes to stderr.
#
# The standalone 'docker-compose' (v1) and 'podman-compose' tools are no longer
# supported by this project — only the '<engine> compose' subcommand is used.

compose_install_hint() {
  local engine="$1"
  local os distro=""
  os="$(uname -s)"

  # Detect the Linux distro id without leaking os-release vars into the shell.
  if [ "$os" = "Linux" ]; then
    distro="$( . /etc/os-release 2>/dev/null && echo "${ID:-}" )"
  fi

  echo "The '$engine compose' command is not available." >&2
  echo "This project needs the Compose plugin (the native '$engine compose' subcommand)." >&2
  echo "The standalone 'docker-compose' / 'podman-compose' tools are no longer supported." >&2
  echo >&2

  if [ "$engine" = "docker" ]; then
    case "$os" in
    Darwin)
      echo "Install Docker Desktop, which bundles Compose:" >&2
      echo "  https://docs.docker.com/desktop/install/mac-install/" >&2
      echo "or, with Homebrew:  brew install --cask docker" >&2
      # Common Homebrew gotcha: 'brew install docker-compose' installs the
      # plugin under /opt/homebrew/lib/docker/cli-plugins, which the docker CLI
      # does not scan on Apple Silicon -- so 'docker compose' still fails even
      # though the plugin is installed. Link it into a dir docker does search.
      if [ -e /opt/homebrew/lib/docker/cli-plugins/docker-compose ]; then
        echo >&2
        echo "The Compose plugin appears to be installed via Homebrew but docker" >&2
        echo "cannot find it. Link it into docker's plugin directory:" >&2
        echo "  mkdir -p ~/.docker/cli-plugins" >&2
        echo "  ln -sf /opt/homebrew/lib/docker/cli-plugins/docker-compose ~/.docker/cli-plugins/docker-compose" >&2
      fi
      ;;
    Linux)
      case "$distro" in
      ubuntu | debian | linuxmint | pop | raspbian)
        echo "Install the Compose plugin:" >&2
        echo "  sudo apt-get update && sudo apt-get install docker-compose-plugin" >&2
        ;;
      fedora | rhel | centos | rocky | almalinux)
        echo "Install the Compose plugin:" >&2
        echo "  sudo dnf install docker-compose-plugin" >&2
        ;;
      *)
        echo "Install the Compose plugin (Linux instructions):" >&2
        echo "  https://docs.docker.com/compose/install/linux/" >&2
        ;;
      esac
      ;;
    *)
      echo "See:  https://docs.docker.com/compose/install/" >&2
      ;;
    esac
  else # podman
    case "$os" in
    Darwin)
      echo "Install/upgrade Podman (the 'podman compose' subcommand ships with recent versions):" >&2
      echo "  brew install podman" >&2
      ;;
    Linux)
      case "$distro" in
      ubuntu | debian | linuxmint | pop | raspbian)
        echo "Upgrade Podman to a version providing 'podman compose':" >&2
        echo "  sudo apt-get update && sudo apt-get install podman" >&2
        ;;
      fedora | rhel | centos | rocky | almalinux)
        echo "Upgrade Podman to a version providing 'podman compose':" >&2
        echo "  sudo dnf install podman" >&2
        ;;
      *)
        echo "See your distribution's docs for a Podman version providing 'podman compose':" >&2
        echo "  https://podman.io/docs/installation" >&2
        ;;
      esac
      ;;
    *)
      echo "See:  https://podman.io/docs/installation" >&2
      ;;
    esac
    echo >&2
    echo "Note: 'podman compose' needs a compose provider to be present." >&2
    echo "If it keeps failing, installing Docker + the Docker Compose plugin is the simplest path." >&2
  fi
}
