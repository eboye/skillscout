#!/usr/bin/env bash
# Installs what building Skillscout needs on Ubuntu 26.04 or Debian testing: the Swift toolchain's
# own dependencies, GTK 4, libadwaita, SQLite, and the tools the packaging scripts run.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  binutils build-essential ca-certificates curl file git gnupg pkg-config tzdata unzip patchelf \
  libcurl4-openssl-dev libedit2 libncurses-dev libsqlite3-dev libxml2-dev zlib1g-dev libuuid1 \
  libgtk-4-dev libadwaita-1-dev desktop-file-utils >/dev/null
