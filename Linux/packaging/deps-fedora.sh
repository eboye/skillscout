#!/usr/bin/env bash
# Installs what building Skillscout needs on Fedora 44 or later: the Swift toolchain's own
# dependencies, GTK 4, libadwaita, SQLite, and the tools the packaging and AppImage scripts run.
set -euo pipefail
dnf install -y -q \
  binutils gcc gcc-c++ glibc-devel libstdc++-devel curl file findutils git gzip tar unzip which patchelf \
  libcurl-devel libedit libuuid ncurses-libs ncurses-devel sqlite-devel libxml2 zlib-devel pkgconf-pkg-config \
  gtk4-devel libadwaita-devel gobject-introspection-devel librsvg2 desktop-file-utils glib2-devel >/dev/null
