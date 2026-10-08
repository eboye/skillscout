#!/usr/bin/env bash
# Builds Skill Cabinet for Linux and installs it: the GNOME app, the skillscout command, the Swift
# runtime they link to, the desktop entry, the icons and the AppStream metadata.
#
#   Linux/scripts/install.sh                      installs into ~/.local
#   PREFIX=/usr DESTDIR="$pkgdir" install.sh      what the PKGBUILD runs
#   SKIP_BUILD=1 install.sh                       installs the last release build
#   STRIP=1 install.sh                            strips the binaries and the Swift runtime
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
prefix="${PREFIX:-$HOME/.local}"
dest="${DESTDIR:-}$prefix"
cd "$root"

if [ -z "${SKIP_BUILD:-}" ]; then
  swift build -c release
fi
build="$(swift build -c release --show-bin-path)"

install -Dm755 "$build/skillscout" "$dest/bin/skillscout"
install -Dm755 "$build/skillscout-gnome" "$dest/bin/skillscout-gnome"

# The Swift runtime libraries the binaries load, found where the toolchain keeps them.
runtime="$dest/lib/skillscout"
mkdir -p "$runtime"
for binary in "$build/skillscout" "$build/skillscout-gnome"; do
  ldd "$binary" | awk '/=> \// { print $3 }' | while read -r library; do
    case "$library" in
      */lib/swift/linux/*) install -Dm644 "$library" "$runtime/$(basename "$library")" ;;
    esac
  done
done

# Only the installed runtime, not the build machine's toolchain.
if command -v patchelf >/dev/null; then
  for binary in "$dest/bin/skillscout" "$dest/bin/skillscout-gnome"; do
    patchelf --set-rpath '$ORIGIN/../lib/skillscout' "$binary"
  done
  for library in "$runtime"/*.so*; do
    patchelf --set-rpath '$ORIGIN' "$library"
  done
fi

# Packages that don't strip on their own, like the .deb and .rpm, ask for it.
if [ -n "${STRIP:-}" ]; then
  strip --strip-unneeded "$dest/bin/skillscout" "$dest/bin/skillscout-gnome" "$runtime"/*.so*
fi

install -Dm644 Linux/com.flaviocopes.skillscout.desktop "$dest/share/applications/com.flaviocopes.skillscout.desktop"
install -Dm644 Linux/com.flaviocopes.skillscout.metainfo.xml "$dest/share/metainfo/com.flaviocopes.skillscout.metainfo.xml"
for icon in Linux/icons/*/com.flaviocopes.skillscout.png; do
  size="$(basename "$(dirname "$icon")")"
  install -Dm644 "$icon" "$dest/share/icons/hicolor/$size/apps/com.flaviocopes.skillscout.png"
done

if [ -z "${DESTDIR:-}" ]; then
  gtk-update-icon-cache -q -t "$prefix/share/icons/hicolor" 2>/dev/null || true
  update-desktop-database -q "$prefix/share/applications" 2>/dev/null || true
fi
echo "Installed Skill Cabinet in $dest"
