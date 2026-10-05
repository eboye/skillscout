#!/usr/bin/env bash
# Packs the tree install.sh stages into an AppImage, with GTK 4, libadwaita and the libraries they
# need inside, through linuxdeploy and its GTK plugin: Linux/packaging/appimage.sh <output>.AppImage
#
# The AppImage still needs a glibc at least as new as the build machine's, so build it on the oldest
# distribution that has libadwaita 1.8.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${1:?where to write the AppImage}"
tools="$root/build/tools"
appdir="$root/build/AppDir"
machine="$(uname -m)"
cd "$root"
mkdir -p "$tools"

linuxdeploy="$tools/linuxdeploy-$machine.AppImage"
plugin="$tools/linuxdeploy-plugin-gtk.sh"
if [ ! -x "$linuxdeploy" ]; then
  curl -sSfL -o "$linuxdeploy" "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$machine.AppImage"
  chmod +x "$linuxdeploy"
fi
if [ ! -x "$plugin" ]; then
  curl -sSfL -o "$plugin" "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/linuxdeploy-plugin-gtk.sh"
  chmod +x "$plugin"
fi

rm -rf "$appdir"
STRIP=1 SKIP_BUILD=1 PREFIX=/usr DESTDIR="$appdir" Linux/scripts/install.sh >/dev/null

# Containers have no FUSE, so the AppImages run from a temporary extraction.
export APPIMAGE_EXTRACT_AND_RUN=1 DEPLOY_GTK_VERSION=4 PATH="$tools:$PATH"
"$linuxdeploy" --appdir "$appdir" --plugin gtk \
  --executable "$appdir/usr/bin/skillscout-gnome" --executable "$appdir/usr/bin/skillscout" \
  --desktop-file "$appdir/usr/share/applications/com.flaviocopes.skillscout.desktop" \
  --icon-file Linux/icons/256x256/com.flaviocopes.skillscout.png

# The GTK plugin forces X11 and the Adwaita GTK theme, for GTK 3. GTK 4 runs on Wayland, and
# libadwaita picks light or dark itself.
sed -i '/export GDK_BACKEND=/d; /export GTK_THEME=/d' "$appdir/apprun-hooks/linuxdeploy-plugin-gtk.sh"

LDAI_OUTPUT="$out" "$linuxdeploy" --appdir "$appdir" --output appimage
echo "$out"
